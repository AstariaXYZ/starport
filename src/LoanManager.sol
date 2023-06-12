pragma solidity =0.8.17;

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";
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
  ConduitTransfer,
  ConduitItemType
} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {
  ConduitInterface
} from "seaport-types/src/interfaces/ConduitInterface.sol";
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
import {
  TokenReceiverInterface
} from "src/interfaces/TokenReceiverInterface.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Originator} from "src/originators/Originator.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {SettlementHandler} from "src/handlers/SettlementHandler.sol";
import {Pricing} from "src/pricing/Pricing.sol";

import "forge-std/console.sol";

contract LoanManager is
  ERC721,
  ContractOffererInterface,
  TokenReceiverInterface
{
  using FixedPointMathLib for uint256;
  uint256 private constant ONE_WORD = 0x20;

  uint96 public loanCount;
  address public feeRecipient;
  uint256 public fee;
  ConsiderationInterface public immutable seaport;
  ConduitControllerInterface public immutable CI;

  enum Action {
    ASK,
    MATCH,
    LOCK,
    UNLOCK
  }

  struct Loan {
    SpentItem collateral;
    ReceivedItem debt;
    address originator;
    address hook;
    address pricing;
    address handler;
    uint256 start;
    uint256 nonce;
    bytes pricingData;
    bytes handlerData;
    bytes hookData;
  }

  struct NewLoanRequest {
    Loan loan;
    Originator.Signature signature;
    bytes details;
  }

  event Lock(uint256 indexed loanId, Loan loan);
  event Unlock(uint256 indexed loanId);
  event SeaportCompatibleContractDeployed();

  error InvalidSender();
  error InvalidAction();
  error InvalidLoan(uint256);
  error InvalidAmount();
  error InvalidDuration();
  error InvalidContext(ContextErrors);

  enum ContextErrors {
    BAD_ORIGINATION,
    LENGTH_MISMATCH,
    BORROWER_MISMATCH,
    COLLATERAL,
    INVALID_PAYMENT,
    ZERO_ADDRESS,
    INVALID_LOAN,
    INVALID_CONDUIT,
    INVALID_RESOLVER
  }

  constructor(ConsiderationInterface consideration) {
    seaport = consideration;
    (, , address conduitController) = consideration.information();
    loanCount = 1;
    CI = ConduitControllerInterface(conduitController);
    emit SeaportCompatibleContractDeployed();
  }

  function name() public view override returns (string memory) {
    return "Loan Manager";
  }

  function symbol() public view override returns (string memory) {
    return "LM";
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
  ) public pure virtual returns (bytes4) {
    return TokenReceiverInterface.onERC721Received.selector;
  }

  function onERC1155Received(
    address,
    address,
    uint256,
    uint256,
    bytes calldata
  ) external pure virtual returns (bytes4) {
    return TokenReceiverInterface.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) external pure virtual returns (bytes4) {
    return TokenReceiverInterface.onERC1155BatchReceived.selector;
  }

  function tokenURI(uint256 tokenId)
    public
    view
    override
    returns (string memory)
  {
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

    if (action == uint8(Action.LOCK)) {
      (offer, consideration) = _previewLock(
        caller,
        fulfiller,
        minimumReceived,
        maximumSpent,
        context
      );
    } else if (action == uint8(Action.UNLOCK)) {
      (offer, consideration) = _previewUnlock(
        caller,
        fulfiller,
        minimumReceived,
        maximumSpent,
        context
      );
    } else {
      revert InvalidAction();
    }
  }

  function _previewLock(
    address caller,
    address fulfiller,
    SpentItem[] calldata minimumReceived,
    SpentItem[] calldata maximumSpent,
    bytes calldata context
  )
    internal
    view
    returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
  {
    consideration = new ReceivedItem[](maximumSpent.length);
    uint256 i = 0;
    for (; i < maximumSpent.length; ) {
      consideration[i] = ReceivedItem({
        itemType: maximumSpent[i].itemType,
        token: maximumSpent[i].token,
        identifier: maximumSpent[i].identifier,
        amount: maximumSpent[i].amount,
        recipient: payable(address(this))
      });
      unchecked {
        ++i;
      }
    }
  }

  function _previewUnlock(
    address caller,
    address fulfiller,
    SpentItem[] calldata minimumReceived,
    SpentItem[] calldata maximumSpent,
    bytes calldata context
  )
    internal
    view
    returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
  {
    (, Loan memory loan) = abi.decode(context, (uint8, Loan));

    bool isLoanHealthy = SettlementHook(loan.hook).isActive(loan);
    uint256 owing = Pricing(loan.pricing).getOwed(loan);
    address payable lender = payable(
      ownerOf(uint256(keccak256(abi.encode(loan))))
    );
    offer = new SpentItem[](1);
    offer[0] = loan.collateral;
    address restricted;
    (consideration, restricted) = SettlementHandler(loan.handler).getSettlement(
      loan,
      maximumSpent,
      owing,
      lender
    );

    if (
      (isLoanHealthy && fulfiller != loan.debt.recipient) ||
      (!isLoanHealthy && restricted != address(0) && fulfiller != restricted)
    ) {
      revert InvalidSender();
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
    pure
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
    (offer, consideration) = previewOrder(
      msg.sender,
      fulfiller,
      minimumReceived,
      maximumSpent,
      context
    );

    if (offer.length > 0) {
      _setOfferApprovals(offer);
    }
  }

  function _setOfferApprovals(SpentItem[] memory offer) internal {
    for (uint256 i = 0; i < offer.length; i++) {
      //approve consideration based on item type
      if (offer[i].itemType == ItemType.ERC1155) {
        ERC1155(offer[i].token).setApprovalForAll(address(seaport), true);
      } else if (offer[i].itemType == ItemType.ERC721) {
        ERC721(offer[i].token).setApprovalForAll(address(seaport), true);
      } else if (offer[i].itemType == ItemType.ERC20) {
        uint256 allowance = ERC20(offer[i].token).allowance(
          address(this),
          address(seaport)
        );
        if (allowance != 0) {
          ERC20(offer[i].token).approve(address(seaport), 0);
        }
        ERC20(offer[i].token).approve(address(seaport), offer[i].amount);
      }
    }
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

    Action action;
    assembly {
      action := calldataload(context.offset)
    }

    if (action == Action.LOCK) {
      _executeLock(consideration, context);
    } else if (action == Action.UNLOCK) {
      _executeUnlock(consideration, context);
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

  function supportsInterface(bytes4 interfaceId)
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
  //  function _executeLoanMatch(bytes calldata context) internal {
  //    //    if (consideration.length != 1) {
  //    //      revert InvalidContext(ContextErrors.LENGTH_MISMATCH);
  //    //    }
  //    (Loan memory ask, LoanManager.NewLoanRequest memory nlr) = abi.decode(
  //      context,
  //      (Loan, LoanManager.NewLoanRequest)
  //    );
  //    if (ownerOf(uint256(keccak256(abi.encode(ask)))) == address(0)) {
  //      revert InvalidContext(ContextErrors.INVALID_LOAN);
  //    }
  //    Loan memory loan = Loan({
  //      validator: validator,
  //      trigger: address(0),
  //      pricing: address(0),
  //      pricing: address(0),
  //      collateral: SpentItem({
  //        itemType: ask.itemType,
  //        token: ask.token,
  //        identifier: ask.identifier,
  //        amount: ask.amount
  //      }),
  //      debt: nlr.ask,
  //      start: block.timestamp,
  //      nonce: ++loanCount,
  //      details: nlr.details
  //    });
  //
  //    //    uint256 beforeBalance = ERC20(nlr.ask.token).balanceOf(
  //    //      nlr.ask.recipient
  //    //    );
  //  }

  function _executeLock(
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
      Loan memory loan = nlrs[i].loan;
      //      if (loan.validator == address(0)) {
      //        revert InvalidContext(ContextErrors.ZERO_ADDRESS);
      //      }
      loan.start = block.timestamp;
      loan.nonce = ++loanCount;

      //setup the lender somewhere here
      Originator.Response memory response = Originator(loan.originator)
        .validate(loan, nlrs[i].details, nlrs[i].signature);
      //      if (lender == address(0)) {
      //        revert InvalidContext(ContextErrors.ZERO_ADDRESS);
      //      }
      if (CI.ownerOf(response.conduit) != loan.originator) {
        revert InvalidContext(ContextErrors.INVALID_CONDUIT);
      }
      if (
        ConduitInterface.execute.selector !=
        ConduitInterface(response.conduit).execute(
          _packageTransfers(loan, response.lender)
        )
      ) {
        revert InvalidContext(ContextErrors.BAD_ORIGINATION);
      }

      bytes memory encodedLoan = abi.encode(loan);
      uint256 loanId = uint256(keccak256(encodedLoan));
      _safeMint(response.lender, loanId, encodedLoan);
      emit Lock(loanId, loan);
      unchecked {
        ++i;
      }
    }
  }

  function _executeUnlock(
    ReceivedItem[] calldata consideration,
    bytes calldata context
  ) internal {
    //make this cheaper, by just encoding the
    uint256 loanId = uint256(keccak256(context[ONE_WORD:]));
    (, Loan memory loan) = abi.decode(context, (uint8, Loan));
    if (
      SettlementHandler.execute.selector !=
      SettlementHandler(loan.handler).execute(loan)
    ) {
      revert InvalidContext(ContextErrors.INVALID_RESOLVER);
    }
    emit Unlock(loanId);
    _burn(loanId);
  }

  function _packageTransfers(LoanManager.Loan memory loan, address lender)
    internal
    view
    returns (ConduitTransfer[] memory transfers)
  {
    ConduitItemType itemType;
    ReceivedItem memory debt = loan.debt;
    assembly {
      itemType := mload(debt)
      switch itemType
      case 1 {

      }
      case 2 {

      }
      case 3 {

      }
      default {
        revert(0, 0) //TODO: Update with error selector - InvalidContext(ContextErrors.INVALID_LOAN)
      }
    }

    uint256 amount;
    if (feeRecipient != address(0) && itemType == ConduitItemType.ERC20) {
      transfers = new ConduitTransfer[](2);
      uint256 feeValue = debt.amount.mulWad(fee);

      amount = debt.amount - feeValue;

      transfers[1] = ConduitTransfer({
        itemType: itemType,
        from: lender,
        token: debt.token,
        identifier: debt.identifier,
        amount: feeValue,
        to: feeRecipient
      });
    } else {
      transfers = new ConduitTransfer[](1);
      amount = debt.amount;
    }

    transfers[0] = ConduitTransfer({
      itemType: itemType,
      from: lender,
      token: debt.token,
      identifier: debt.identifier,
      amount: amount,
      to: debt.recipient
    });
  }
}
