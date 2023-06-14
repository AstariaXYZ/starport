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

contract FeeRecipient {
  address public feeRecipient;

  constructor(address feeRecipient_) {
    feeRecipient = feeRecipient_;
  }

  modifier onlyFeeRecipient() {
    require(msg.sender == feeRecipient, "LoanManager: not fee recipient");
    _;
  }
}

contract LoanManager is ERC721, ContractOffererInterface {
  using FixedPointMathLib for uint256;

  //  uint96 public count;
  address public immutable custodian;
  address public feeRecipient;
  ConsiderationInterface public immutable seaport;
  uint256 public fee;
  uint256 private constant ONE_WORD = 0x20;

  enum FieldFlags {
    INITIALIZED,
    INACTIVE
  }

  //  enum Action {
  //    ASK,
  //    MATCH,
  //    LOCK
  //  }
  struct Terms {
    address hook;
    address pricing;
    address handler;
    bytes pricingData;
    bytes handlerData;
    bytes hookData;
  }
  struct Loan {
    uint256 start;
    address borrower;
    address originator;
    SpentItem[] collateral;
    SpentItem[] debt;
    Terms terms;
  }

  struct NewLoanRequest {
    address borrower;
    address originator;
    Originator.Signature signature;
    SpentItem[] debt;
    bytes details;
    bytes32 hash;
  }

  event Open(uint256 loanId, LoanManager.Loan loan);
  event SeaportCompatibleContractDeployed();

  error InvalidSender();
  error InvalidAction();
  error InvalidLoan(uint256);
  error InvalidAmount();
  error InvalidDuration();
  error InvalidContext(ContextErrors);

  enum ContextErrors {
    INVALID_STATE,
    BAD_ORIGINATION,
    LENDER_ERROR,
    LENGTH_MISMATCH,
    BORROWER_MISMATCH,
    COLLATERAL,
    INVALID_PAYMENT,
    ZERO_ADDRESS,
    INVALID_LOAN,
    INVALID_CONDUIT,
    INVALID_RESOLVER,
    INVALID_COLLATERAL
  }

  constructor(ConsiderationInterface consideration) {
    seaport = consideration;
    custodian = address(new Custodian(this, address(consideration)));
    emit SeaportCompatibleContractDeployed();
    //    count = 1;
  }

  function name() public pure override returns (string memory) {
    return "Loan Manager";
  }

  function symbol() public pure override returns (string memory) {
    return "LM";
  }

  // MODIFIERS
  modifier onlySeaport() {
    if (msg.sender != address(seaport)) {
      revert InvalidSender();
    }
    _;
  }

  function tokenURI(
    uint256 tokenId
  ) public view override returns (string memory) {
    return string(abi.encodePacked("https://astaria.xyz/loans?id=", tokenId));
  }

  function burn(uint256 tokenId) external {
    if (msg.sender != address(custodian)) {
      revert InvalidSender();
    }
    _transfer(ownerOf(tokenId), address(1), tokenId);
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
    //only used for off chain computation of the complete offer
    if (caller != address(seaport)) {
      LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
      bytes memory loanTemplateEncoded = abi.encode(loan);
      //offer this up in the generateOrder flow

      bytes32 loanHash = keccak256(loanTemplateEncoded);
      offer = new SpentItem[](1);
      offer[0] = SpentItem({
        itemType: ItemType.ERC721,
        token: address(this),
        identifier: uint256(loanHash),
        amount: 1
      });
    }
    consideration = new ReceivedItem[](maximumSpent.length);
    for (uint256 i = 0; i < maximumSpent.length; ) {
      consideration[i] = ReceivedItem({
        itemType: maximumSpent[i].itemType,
        token: maximumSpent[i].token,
        identifier: maximumSpent[i].identifier,
        amount: maximumSpent[i].amount,
        recipient: payable(custodian)
      });
      unchecked {
        ++i;
      }
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
    returns (string memory, Schema[] memory schemas)
  {
    schemas = new Schema[](1);
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
    (, consideration) = previewOrder(
      msg.sender,
      fulfiller,
      minimumReceived,
      maximumSpent,
      context
    );
    LoanManager.NewLoanRequest memory nlr = abi.decode(
      context,
      (LoanManager.NewLoanRequest)
    );

    address borrower = nlr.borrower;
    Originator.Response memory response = Originator(nlr.originator).execute(
      Originator.ExecuteParams({
        //        loanId: loanId,
        borrower: borrower,
        collateral: minimumReceived,
        debt: nlr.debt,
        nlrDetails: nlr.details,
        signature: nlr.signature
      })
    );
    Loan memory loan = response.loan;
    bytes memory loanTemplateEncoded = abi.encode(loan);
    //offer this up in the generateOrder flow
    bytes32 loanHash = keccak256(loanTemplateEncoded);
    if (loanHash != nlr.hash) {
      revert InvalidContext(ContextErrors.BAD_ORIGINATION);
    }
    if (fulfiller != borrower) {
      offer = new SpentItem[](1);
      offer[0] = SpentItem({
        itemType: ItemType.ERC721,
        token: address(this),
        identifier: uint256(loanHash),
        amount: 1
      });
    }

    loan.start = block.timestamp; //write to the extra data
    bytes memory encodedLoan = abi.encode(loan);

    uint256 loanId = uint256(keccak256(encodedLoan));

    _safeMint(response.issuer, loanId, encodedLoan);
    emit Open(loanId, loan);
  }

  function transferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public payable override {
    if (from == address(this)) {
      return;
    }
    super.transferFrom(from, to, tokenId);
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

    //    LoanManager.NewLoanRequest memory nlr = abi.decode(
    //      context,
    //      (LoanManager.NewLoanRequest)
    //    );
    //    //    Loan memory loan = nlr.loan;
    //    //    loan.borrower = nlr.borrower;
    //    //    loan.originator = nlr.originator;
    //    //    loan.terms = nlr.terms;
    //    //
    //    //    _setCollateral(loan, consideration);
    //
    //    Originator.Response memory response = Originator(nlr.originator).execute(
    //      Originator.ExecuteParams({
    //        //        loanId: loanId,
    //        borrower: nlr.borrower,
    //        collateral: _setCollateral(consideration),
    //        debt: nlr.debt,
    //        nlrDetails: nlr.details,
    //        signature: nlr.signature
    //      })
    //    );
    //    bytes memory loanTemplateEncoded = abi.encode(response.loan);
    //    //offer this up in the generateOrder flow
    //    //
    //    Loan memory loan = response.loan;
    //    bytes32 loanHash = keccak256(loanTemplateEncoded);
    //    if (loanHash != nlr.hash) {
    //      revert InvalidContext(ContextErrors.BAD_ORIGINATION);
    //    }
    //    //    loan.borrower = nlr.borrower;
    //    //    loan.start = block.timestamp;//write to the extra data
    //    loan.nonce = contractNonce;
    //    bytes memory encodedLoan = abi.encode(loan);
    //
    //    uint256 loanId = uint256(loanHash);
    //
    //    _safeMint(response.issuer, loanId, encodedLoan);
    //    emit Open(loanId, loan);

    ratifyOrderMagicValue = ContractOffererInterface.ratifyOrder.selector;
  }

  function _isLoanStarted(uint256 tokenId) internal view returns (bool) {
    return _getExtraData(tokenId) > uint8(FieldFlags.INACTIVE);
  }

  //  function mint(LoanManager.Loan calldata loan) external {
  //    bytes memory encodedLoan = abi.encode(loan);
  //    uint256 loanId = uint256(keccak256(encodedLoan));
  //    if (!_isLoanStarted(loanId)) {
  //      revert InvalidContext(ContextErrors.INVALID_STATE);
  //    }
  //    _safeMint(loan.issuer, loanId, encodedLoan);
  //  }

  //  function _getAction(
  //    bytes calldata context
  //  ) internal pure returns (Action action) {
  //    assembly {
  //      action := calldataload(context.offset)
  //    }
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

  function _setCollateral(
    ReceivedItem[] memory consideration
  ) internal pure returns (SpentItem[] memory collateral) {
    //spent item
    collateral = new SpentItem[](consideration.length);
    for (uint256 i = 0; i < consideration.length; i++) {
      collateral[i] = SpentItem({
        itemType: consideration[i].itemType,
        token: consideration[i].token,
        identifier: collateral[i].identifier,
        amount: consideration[i].amount
      });
    }
  }
}

contract Custodian is ContractOffererInterface, TokenReceiverInterface {
  LoanManager public immutable LM;
  address public immutable seaport;
  event Close(uint256 indexed loanId);

  constructor(LoanManager LM_, address seaport_) {
    seaport = seaport_;
    LM = LM_;
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(ContractOffererInterface) returns (bool) {
    return interfaceId == type(ContractOffererInterface).interfaceId;
  }

  modifier onlySeaport() {
    if (msg.sender != address(seaport)) {
      revert InvalidSender();
    }
    _;
  }

  error InvalidSender();
  error InvalidAction();
  error InvalidLoan(uint256);
  error InvalidAmount();
  error InvalidDuration();
  error InvalidContext(ContextErrors);

  enum ContextErrors {
    BAD_ORIGINATION,
    LENDER_ERROR,
    LENGTH_MISMATCH,
    BORROWER_MISMATCH,
    COLLATERAL,
    INVALID_PAYMENT,
    ZERO_ADDRESS,
    INVALID_LOAN,
    INVALID_CONDUIT,
    INVALID_RESOLVER,
    INVALID_COLLATERAL
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

    LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
    uint256 loanId = uint256(keccak256(abi.encode(loan)));
    if (
      SettlementHandler.execute.selector !=
      SettlementHandler(loan.terms.handler).execute(loan)
    ) {
      revert InvalidContext(ContextErrors.INVALID_RESOLVER);
    }
    emit Close(loanId);
    LM.burn(loanId);

    return ContractOffererInterface.ratifyOrder.selector;
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
    LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
    offer = loan.collateral;
    ReceivedItem memory feeConsideration = Originator(loan.originator)
      .getFeeConsideration(loan);
    if (SettlementHook(loan.terms.hook).isActive(loan)) {
      if (fulfiller != loan.borrower) {
        revert InvalidSender();
      }
      //TODO: add in fee enforcement?
      consideration = Pricing(loan.terms.pricing).getPaymentConsideration(loan);

      //      consideration = new ReceivedItem[](paymentConsideration.length);
      //      consideration[0] = feeConsideration;
    } else {
      address restricted;
      (consideration, restricted) = SettlementHandler(loan.terms.handler)
        .getSettlement(loan, minimumReceived);

      if (restricted != address(0) && fulfiller != restricted) {
        revert InvalidSender();
      }
    }
  }

  function getSeaportMetadata()
    external
    pure
    returns (string memory, Schema[] memory schemas)
  {
    schemas = new Schema[](1);
    schemas[0] = Schema(8, "");
    return ("Loans", schemas);
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
}
