pragma solidity =0.8.17;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {
  ConduitTransfer,
  ConduitItemType
} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {
  ItemType,
  OfferItem,
  Schema,
  SpentItem,
  ReceivedItem,
  OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {
  ConduitControllerInterface
} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {
  ConsiderationInterface
} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {
  ConduitInterface
} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {
  ContractOffererInterface
} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";
import {
  TokenReceiverInterface
} from "src/interfaces/TokenReceiverInterface.sol";
import {Validator} from "src/interfaces/Validator.sol";

contract LoanManager is
  ERC721("LoanManager", "LM"),
  AmountDeriver,
  ContractOffererInterface,
  TokenReceiverInterface
{
  uint256 private constant MIN_DURATION = 1 hours;

  enum Action {
    OPEN,
    CLOSE
  }

  struct BorrowerDetails {
    address who;
    address what;
    uint256 howMuch;
  }

  struct NewLoanRequest {
    address lender;
    BorrowerDetails borrowerDetails;
    uint8 v;
    bytes32 r;
    bytes32 s;
    bytes details;
  }

  event LoanOpened(uint256 indexed loanId, Validator.Loan loan);
  event LoanClosed(uint256 indexed loanId, uint256 amount, bool liquidated);
  event SeaportCompatibleContractDeployed();

  error InvalidSender();
  error InvalidAction();
  error InvalidLoan(uint256);
  error InvalidAmount();
  error InvalidDuration();
  error InvalidContext(ContextErrors);

  enum ContextErrors {
    LENGTH_MISMATCH,
    BORROWER_MISMATCH,
    COLLATERAL,
    INVALID_PAYMENT,
    ZERO_ADDRESS,
    INVALID_LOAN
  }

  error InvalidCollateral();
  error LoanHealthy();
  error StateMismatch(uint256);
  error UnsupportedExtraDataVersion(uint8 version);
  error InvalidExtraDataEncoding(uint8 version);

  ConsiderationInterface public seaport;

  uint256 public loanCount;

  constructor(ConsiderationInterface consideration) {
    seaport = consideration;
    loanCount = 1;
    emit SeaportCompatibleContractDeployed();
  }

  // MODIFIERS
  modifier onlySeaport() {
    if (msg.sender != address(seaport)) {
      revert InvalidSender();
    }
    _;
  }

  // PUBLIC FUNCTIONS
  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) public virtual returns (bytes4) {
    return TokenReceiverInterface.onERC721Received.selector;
  }

  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) external virtual returns (bytes4) {
    return TokenReceiverInterface.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external virtual returns (bytes4) {
    return TokenReceiverInterface.onERC1155BatchReceived.selector;
  }

  function tokenURI(
    uint256 tokenId
  ) public view override returns (string memory) {
    return string(abi.encodePacked("https://astaria.xyz/loans?id=", tokenId));
  }

  /**
   * @dev previews the order for this contract offerer.
   *
   * @param caller        The address of the contract fulfiller.
   * @param fulfiller        The address of the contract fulfiller.
   * @param minimumReceived  The minimum the fulfiller must receive.
   * @param maximumSpent     The most a fulfiller will spend
   * @param context          The context of the order.
   * @return offer     The items spent by the order.
   * @return consideration  The items received by the order.
   */
  function previewOrder(
    address caller,
    address fulfiller,
    SpentItem[] calldata minimumReceived,
    SpentItem[] calldata maximumSpent,
    bytes calldata context // encoded based on the schemaID
  )
    public
    view
    returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
  {
    uint8 action = abi.decode(context[:32], (uint8));

    if (action == uint8(Action.OPEN)) {
      consideration = new ReceivedItem[](maximumSpent.length);
      for (uint256 i = 0; i < maximumSpent.length; i++) {
        consideration[i] = ReceivedItem({
          itemType: maximumSpent[i].itemType,
          token: maximumSpent[i].token,
          identifier: maximumSpent[i].identifier,
          amount: maximumSpent[i].amount,
          recipient: payable(address(this))
        });
      }
    } else if (action == uint8(Action.CLOSE)) {
      (, Validator.Loan memory loan) = abi.decode(
        context,
        (uint8, Validator.Loan)
      );
      (uint256 owed, uint256 settlementPrice) = Validator(loan.validator)
        .getSettlementData(loan);

      if (loan.start + loan.duration < block.timestamp) {
        if (maximumSpent[0].amount < owed) {
          revert InvalidAmount();
        }

        consideration = new ReceivedItem[](1);
        consideration[0] = ReceivedItem({
          itemType: ItemType.ERC20,
          token: loan.debtToken,
          identifier: 0,
          amount: owed,
          recipient: payable(ownerOf(uint256(keccak256(abi.encode(loan)))))
        });
      } else {
        //now were in liquidation
        offer = new SpentItem[](1);
        offer[0] = SpentItem({
          itemType: loan.itemType,
          token: loan.token,
          identifier: loan.identifier,
          amount: loan.identifierAmount
        });

        (uint256 startPrice, uint256 endPrice, uint256 auctionDuration) = abi
          .decode(loan.extraData, (uint256, uint256, uint256));
        consideration = new ReceivedItem[](2);

        if (maximumSpent[0].amount < settlementPrice) {
          revert InvalidAmount();
        }
        consideration[0] = ReceivedItem({
          itemType: ItemType.ERC20,
          token: loan.debtToken,
          identifier: 0,
          amount: settlementPrice,
          recipient: payable(ownerOf(uint256(keccak256(abi.encode(loan)))))
        });
        consideration[1] = ReceivedItem({
          itemType: ItemType.ERC20,
          token: loan.token,
          identifier: loan.identifier,
          amount: maximumSpent[0].amount - settlementPrice,
          recipient: payable(loan.borrower)
        });
      }
    } else {
      revert InvalidAction();
    }
  }

  /**
   * @dev Gets the metadata for this contract offerer.
   *
   * @return name    The name of the contract offerer.
   * @return schemas The schemas supported by the contract offerer.
   */
  function getSeaportMetadata()
    external
    view
    returns (string memory name, Schema[] memory schemas)
  {
    schemas = new Schema[](1);
    uint256 schemaId = uint256(8);
    schemas[0] = Schema(8, "");
    return ("Loans", schemas);
  }

  /**
   * @dev Generates the order for this contract offerer.
   *
   * @param fulfiller        The address of the contract fulfiller.
   * @param maximumSpent     The maximum amount of items to be spent by the order.
   * @param context          The context of the order.
   * @return offer           The items spent by the order.
   * @return consideration   The items received by the order.
   */
  function generateOrder(
    address fulfiller,
    SpentItem[] calldata minimumReceived,
    SpentItem[] calldata maximumSpent,
    bytes calldata context // encoded based on the schemaID
  )
    external
    onlySeaport
    returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
  {
    return
      previewOrder(
        msg.sender,
        fulfiller,
        minimumReceived,
        maximumSpent,
        context
      );
  }

  /**
   * @dev Generates the order for this contract offerer.
   *
   * @param offer            The address of the contract fulfiller.
   * @param consideration    The maximum amount of items to be spent by the order.
   * @param context          The context of the order.
   * @param orderHashes      The context of the order.
   * @param contractNonce    The context of the order.
   * @return ratifyOrderMagicValue The magic value returned by the ratify.
   */
  function ratifyOrder(
    SpentItem[] calldata offer,
    ReceivedItem[] calldata consideration,
    bytes calldata context, // encoded based on the schemaID
    bytes32[] calldata orderHashes,
    uint256 contractNonce
  ) external onlySeaport returns (bytes4 ratifyOrderMagicValue) {
    //get the spent token and amount from the spent item

    uint8 action = abi.decode(context[:32], (uint8));

    if (action == uint8(Action.OPEN)) {
      _executeLoanOpen(consideration, context);
    } else if (action == uint8(Action.CLOSE)) {
      _executeLoanClosed(consideration, context);
    } else {
      revert InvalidAction();
    }

    return ContractOffererInterface.ratifyOrder.selector;
  }

  //do more work here
  function forgive(Validator.Loan calldata loan) public {
    uint256 loanId = uint256(keccak256(abi.encode(loan)));
    if (msg.sender != ownerOf(loanId)) {
      revert InvalidSender();
    }

    _burn(loanId);

    ERC721(loan.token).transferFrom(address(this), msg.sender, loan.identifier);
  }

  function supportsInterface(
    bytes4 interfaceId
  )
    public
    view
    virtual
    override(ERC721, ContractOffererInterface)
    returns (bool)
  {
    return
      interfaceId == type(ContractOffererInterface).interfaceId ||
      interfaceId == type(ERC721).interfaceId ||
      super.supportsInterface(interfaceId);
  }

  // INTERNAL FUNCTIONS

  function _executeLoanOpen(
    ReceivedItem[] calldata consideration,
    bytes calldata context
  ) internal {
    (, LoanManager.NewLoanRequest[] memory nlrs) = abi.decode(
      context,
      (uint8, LoanManager.NewLoanRequest[])
    );

    if (nlrs.length != consideration.length) {
      revert InvalidContext(ContextErrors.LENGTH_MISMATCH);
    }
    uint256 i = 0;
    for (; i < nlrs.length; ) {
      address validator;
      bytes memory data = nlrs[i].details;
      assembly {
        validator := mload(add(data, 64))
      }
      if (validator == address(0)) {
        revert InvalidContext(ContextErrors.ZERO_ADDRESS);
      }

      uint256 beforeBalance = ERC20(nlrs[i].borrowerDetails.what).balanceOf(
        nlrs[i].borrowerDetails.who
      );
      (Validator.Loan memory loan, address lender) = Validator(validator)
        .execute(nlrs[i], consideration[i]);
      uint256 afterBalance = ERC20(nlrs[i].borrowerDetails.what).balanceOf(
        nlrs[i].borrowerDetails.who
      );
      if (afterBalance - beforeBalance != nlrs[i].borrowerDetails.howMuch) {
        revert InvalidContext(ContextErrors.INVALID_PAYMENT);
      }
      if (loan.borrower != nlrs[i].borrowerDetails.who) {
        revert InvalidContext(ContextErrors.BORROWER_MISMATCH);
      }
      if (
        loan.itemType != consideration[i].itemType ||
        loan.token != consideration[i].token ||
        loan.identifier != consideration[i].identifier ||
        loan.identifierAmount != consideration[i].amount
      ) {
        revert InvalidContext(ContextErrors.INVALID_LOAN);
      }
      //            if (loan.duration < MIN_DURATION) {
      //                revert InvalidDuration();
      //            }
      loan.nonce = ++loanCount;
      uint256 loanId = uint256(keccak256(abi.encode(loan)));
      _safeMint(lender, loanId);
      emit LoanOpened(loanId, loan);
      unchecked {
        ++i;
      }
    }
  }

  function _executeLoanClosed(
    ReceivedItem[] calldata consideration,
    bytes calldata context
  ) internal {
    Validator.Loan memory loan = abi.decode(context[32:], (Validator.Loan));

    uint256 loanId = uint256(keccak256(abi.encode(loan)));

    bool liquidated = true;
    if (loan.start + loan.duration > block.timestamp) {
      ERC721(loan.token).safeTransferFrom(
        address(this),
        loan.borrower,
        loan.identifier,
        ""
      );
      liquidated = false;
    }
    emit LoanClosed(loanId, consideration[0].amount, liquidated);
    _burn(loanId);
  }
}
