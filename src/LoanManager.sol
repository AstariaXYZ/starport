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
import {Validator} from "src/validators/Validator.sol";
import "forge-std/console.sol";
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
  struct Loan {
    SpentItem collateral;
    ReceivedItem debt;
    address validator;
    uint256 start;
    uint256 nonce;
    bytes details;
  }


  struct NewLoanRequest {
    address lender;
    ReceivedItem ask;
    Validator.Signature signature;
    bytes details;
  }

  event LoanOpened(uint256 indexed loanId, Loan loan);
  event LoanClosed(uint256 indexed loanId, ReceivedItem[] consideration);
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
      (, Loan memory loan) = abi.decode(context, (uint8, Loan));

      if (
        Validator(loan.validator).isLoanHealthy(loan) &&
        fulfiller != loan.debt.recipient
      ) {
        revert InvalidSender();
      }

      //now were in liquidation
      offer = new SpentItem[](1);
      offer[0] = loan.collateral;

      consideration = Validator(loan.validator).getClosedConsideration(
        loan,
        maximumSpent[0]
      );
      //otherwise compute the ownership of the loan based on liquidation or not
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
  //  function forgive(Loan calldata loan) public {
  //    uint256 loanId = uint256(keccak256(abi.encode(loan)));
  //    if (msg.sender != ownerOf(loanId)) {
  //      revert InvalidSender();
  //    }
  //
  //    _burn(loanId);
  //
  //    ERC721(loan.token).transferFrom(address(this), msg.sender, loan.identifier);
  //  }

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

      assembly {
        validator := calldataload(add(context.offset, 480))
      }
      if (validator == address(0)) {
        revert InvalidContext(ContextErrors.ZERO_ADDRESS);
      }

      uint256 beforeBalance = ERC20(nlrs[i].ask.token).balanceOf(
        nlrs[i].ask.recipient
      );
      Loan memory loan = Loan({
        collateral: SpentItem({
          itemType: consideration[i].itemType,
          token: consideration[i].token,
          identifier: consideration[i].identifier,
          amount: consideration[i].amount
        }),
        debt: nlrs[i].ask,
        validator: validator,
        start: block.timestamp,
        nonce: ++loanCount,
        details: nlrs[i].details
      });
      address recipient = Validator(validator).execute(
        loan,
        nlrs[i].signature,
        consideration[i]
      );

      uint256 afterBalance = ERC20(loan.debt.token).balanceOf(
        loan.debt.recipient
      );
      if (afterBalance - beforeBalance != nlrs[i].ask.amount) {
        revert InvalidContext(ContextErrors.INVALID_PAYMENT);
      }
      uint256 loanId = uint256(keccak256(abi.encode(loan)));
      _safeMint(recipient, loanId);
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
    //make this cheaper, by just encoding the
    //    Loan memory loan = abi.decode(context[32:], (Loan));
    uint256 loanId = uint256(keccak256(context[32:]));
    emit LoanClosed(loanId, consideration);
    _burn(loanId);
  }
}
