pragma solidity =0.8.17;

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";

import {
  ItemType,
  OfferItem,
  Schema,
  SpentItem,
  ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

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

import {Custodian} from "src/Custodian.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {Constants} from "src/Constants.sol";

contract LoanManager is ERC721, ContractOffererInterface, Constants {
  using FixedPointMathLib for uint256;

  address public immutable custodian;
  //  address public feeRecipient;
  address public constant seaport =
    address(0x2e234DAe75C793f67A35089C9d99245E1C58470b);
  //  uint256 public fee;
  //  uint256 private constant ONE_WORD = 0x20;

  enum FieldFlags {
    INITIALIZED,
    INACTIVE
  }

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

  struct Obligation {
    bytes32 hash;
    address originator;
    bool isTrusted;
    Originator.Request ask;
  }

  event Close(uint256 loanId);
  event Open(uint256 loanId, LoanManager.Loan loan);
  event SeaportCompatibleContractDeployed();

  error InvalidSender();
  error InvalidAction();
  error InvalidLoan(uint256);
  error InvalidAmount();
  error InvalidDuration();
  error InvalidSignature();
  error InvalidOrigination();
  error InvalidSigner();
  error InvalidContext(ContextErrors);

  enum ContextErrors {
    BAD_ORIGINATION,
    INVALID_PAYMENT,
    LENGTH_MISMATCH,
    BORROWER_MISMATCH,
    COLLATERAL,
    ZERO_ADDRESS,
    INVALID_LOAN,
    INVALID_CONDUIT,
    INVALID_RESOLVER,
    INVALID_COLLATERAL
  }

  constructor() {
    custodian = address(new Custodian(this, seaport));
    emit SeaportCompatibleContractDeployed();
  }

  function name() public pure override returns (string memory) {
    return "Astaria Loan Manager";
  }

  function symbol() public pure override returns (string memory) {
    return "ALM";
  }

  // MODIFIERS
  modifier onlySeaport() {
    if (msg.sender != seaport) {
      revert InvalidSender();
    }
    _;
  }

  function tokenURI(
    uint256 tokenId
  ) public view override returns (string memory) {
    return string(abi.encodePacked("https://astaria.xyz/loans?id=", tokenId));
  }

  function settle(uint256 tokenId) external {
    if (msg.sender != address(custodian)) {
      revert InvalidSender();
    }
    emit Close(tokenId);
    _transfer(_ownerOf(tokenId), address(1), tokenId);
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
    consideration = new ReceivedItem[](maximumSpent.length);
    uint256 i = 0;
    for (; i < maximumSpent.length; ) {
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

  function _emptyTerms() internal pure returns (Terms memory) {
    return
      Terms({
        hook: address(0),
        pricing: address(0),
        handler: address(0),
        pricingData: "",
        handlerData: "",
        hookData: ""
      });
  }

  function _fillObligationAndVerify(
    address fulfiller,
    LoanManager.Obligation memory obligation,
    SpentItem[] calldata maximumSpentFromBorrower
  ) internal returns (SpentItem[] memory offer) {
    address borrower = obligation.ask.borrower;
    bool isTrustedExecution = obligation.isTrusted || fulfiller != borrower;

    if (!isTrustedExecution) {
      obligation.ask.borrower = address(this);
    }

    //make template

    Originator.Response memory response = Originator(obligation.originator)
      .execute(obligation.ask);
    Loan memory loan = Loan({
      start: uint(0),
      borrower: borrower,
      originator: !isTrustedExecution ? address(0) : obligation.originator,
      collateral: maximumSpentFromBorrower,
      debt: obligation.ask.debt,
      terms: response.terms
    });
    // we settle via seaport channels if a match is happening
    if (!isTrustedExecution) {
      //      loan.terms = response.terms;
      //      _cmpBeforeAfter(
      //        balancesBefore,
      //        _getBalance(borrower, obligation.ask.debt),
      //        obligation.ask.debt
      //      );
      bytes32 loanHash = keccak256(abi.encode(loan));
      if (loanHash != obligation.hash) {
        revert InvalidOrigination();
      }

      offer = _setOffer(loan.debt, loanHash);
      _setDebtApprovals(obligation.ask.debt);
    }

    loan.start = block.timestamp;
    loan.originator = obligation.originator;
    _issueLoanManager(loan, response.issuer);
  }

  function _issueLoanManager(Loan memory loan, address issuer) internal {
    bytes memory encodedLoan = abi.encode(loan);

    uint256 loanId = uint256(keccak256(encodedLoan));

    _safeMint(issuer, loanId, encodedLoan);
    emit Open(loanId, loan);
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
    LoanManager.Obligation memory obligation = abi.decode(
      context,
      (LoanManager.Obligation)
    );

    offer = _fillObligationAndVerify(fulfiller, obligation, maximumSpent);
  }

  function _setDebtApprovals(SpentItem[] memory debt) internal {
    uint256 i = 0;
    for (; i < debt.length; ) {
      //approve consideration based on item type
      if (debt[i].itemType != ItemType.ERC20) {
        ERC721(debt[i].token).setApprovalForAll(seaport, true);
      } else {
        ERC20(debt[i].token).approve(seaport, debt[i].amount);
      }
      unchecked {
        ++i;
      }
    }
  }

  function _setOffer(
    SpentItem[] memory debt,
    bytes32 loanHash
  ) internal view returns (SpentItem[] memory offer) {
    offer = new SpentItem[](debt.length + 1);
    offer[0] = SpentItem({
      itemType: ItemType.ERC721,
      token: address(this),
      identifier: uint256(loanHash),
      amount: 1
    });
    uint256 i = 0;

    for (; i < debt.length; ) {
      offer[i + 1] = debt[i];
      unchecked {
        ++i;
      }
    }
  }

  function _cmpBeforeAfter(
    uint256[] memory balancesBefore,
    uint256[] memory balancesAfter,
    SpentItem[] memory expectedDeltaIncrease
  ) internal view {
    uint i = 0;
    for (; i < balancesBefore.length; ) {
      if (
        balancesAfter[i] != balancesBefore[i] + expectedDeltaIncrease[i].amount
      ) {
        revert InvalidContext(ContextErrors.INVALID_PAYMENT);
      }
      unchecked {
        ++i;
      }
    }
  }

  function _getBalance(
    address target,
    ItemType itemType,
    address token,
    uint256 identifier
  ) internal view returns (uint256) {
    if (itemType == ItemType.ERC721) {
      return ERC721(token).ownerOf(identifier) == address(target) ? 1 : 0;
    } else if (itemType == ItemType.ERC1155) {
      return ERC1155(token).balanceOf(target, uint256(identifier));
    } else {
      return ERC20(token).balanceOf(target);
    }
  }

  function _getBalance(
    address target,
    SpentItem[] memory before
  ) internal view returns (uint256[] memory balances) {
    balances = new uint256[](before.length);
    uint256 i = 0;
    for (; i < before.length; ) {
      balances[i] = _getBalance(
        target,
        before[i].itemType,
        before[i].token,
        before[i].identifier
      );
      unchecked {
        ++i;
      }
    }
  }

  function transferFrom(
    address from,
    address to,
    uint256 tokenId
  ) public payable override {
    if (from != address(this)) super.transferFrom(from, to, tokenId);
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
    ratifyOrderMagicValue = ContractOffererInterface.ratifyOrder.selector;
  }

  function _isLoanStarted(uint256 tokenId) internal view returns (bool) {
    return _getExtraData(tokenId) > uint8(FieldFlags.INACTIVE);
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
}
