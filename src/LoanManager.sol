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
  ConsiderationInterface
} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Originator} from "src/originators/Originator.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {SettlementHandler} from "src/handlers/SettlementHandler.sol";
import {Pricing} from "src/pricing/Pricing.sol";

import {StarPortLib} from "src/lib/StarPortLib.sol";

import "forge-std/console2.sol";
import {
  ConduitTransfer,
  ConduitItemType
} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {
  ConduitControllerInterface
} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {
  ConduitInterface
} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {Custodian} from "src/Custodian.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {CaveatEnforcer} from "src/enforcers/CaveatEnforcer.sol";

import {ConduitHelper} from "src/ConduitHelper.sol";

contract LoanManager is ERC721, ContractOffererInterface, ConduitHelper {
  using FixedPointMathLib for uint256;
  using {StarPortLib.toReceivedItems} for SpentItem[];
  using {StarPortLib.getId} for LoanManager.Loan;

  ConsiderationInterface public constant seaport =
    ConsiderationInterface(0x2e234DAe75C793f67A35089C9d99245E1C58470b);
  //  ConsiderationInterface public constant seaport =
  //    ConsiderationInterface(0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC); // mainnet
  address public immutable defaultCustodian;
  bytes32 public immutable DEFAULT_CUSTODIAN_CODE_HASH;
  //  uint256 public fee;
  //  uint256 private constant ONE_WORD = 0x20;

  // Define the EIP712 domain and typehash constants for generating signatures
  bytes32 constant EIP_DOMAIN =
    keccak256(
      "EIP712Domain(string version,uint256 chainId,address verifyingContract)"
    );
  bytes32 public constant INTENT_ORIGINATION_TYPEHASH =
    keccak256("IntentOrigination(bytes32 hash,bytes32 salt,uint256 nonce)");
  bytes32 constant VERSION = keccak256("0");

  bytes32 internal immutable _DOMAIN_SEPARATOR;

  //TODO: we need to add in type hashes into the hashes
  mapping(bytes32 => bool) public usedHashes;
  mapping(address => uint256) public borrowerNonce; //needs to be invalidated

  enum FieldFlags {
    INITIALIZED,
    ACTIVE,
    INACTIVE
  }

  struct Terms {
    address hook; //the address of the hookmodule
    bytes hookData; //bytes encoded hook data
    address pricing; //the address o the pricing module
    bytes pricingData; //bytes encoded pricing data
    address handler; //the address of the handler module
    bytes handlerData; //bytes encoded handler data
  }

  struct Loan {
    uint256 start; //start of the loan
    address custodian; //where the collateral is being held
    address borrower; //the borrower
    address issuer; //the capital issuer/lender
    address originator; //who originated the loan
    SpentItem[] collateral; //array of collateral
    SpentItem[] debt; //array of debt
    Terms terms; //the actionable terms of the loan
  }

  struct Caveat {
    address enforcer;
    bytes terms;
  }

  struct Obligation {
    address custodian;
    address originator;
    address borrower;
    bytes32 salt;
    SpentItem[] debt;
    Caveat[] caveats;
    bytes details;
    bytes signature;
  }

  event Close(uint256 loanId);
  event Open(uint256 loanId, LoanManager.Loan loan);
  event SeaportCompatibleContractDeployed();

  error ConduitTransferError();
  error InvalidConduit();
  error InvalidRefinance();
  error InvalidSender();
  error InvalidAction();
  error InvalidLoan(uint256);
  error InvalidMaximumSpentEmpty();
  error InvalidDebtEmpty();
  error InvalidAmount();
  error InvalidDuration();
  error InvalidSignature();
  error InvalidOrigination();
  error InvalidSigner();
  error InvalidContext(ContextErrors);
  error InvalidNoRefinanceConsideration();

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
    address custodian = address(new Custodian(this, address(seaport)));

    bytes32 defaultCustodianCodeHash;
    assembly {
      defaultCustodianCodeHash := extcodehash(custodian)
    }
    defaultCustodian = custodian;
    DEFAULT_CUSTODIAN_CODE_HASH = defaultCustodianCodeHash;
    _DOMAIN_SEPARATOR = keccak256(
      abi.encode(EIP_DOMAIN, VERSION, block.chainid, address(this))
    );
    emit SeaportCompatibleContractDeployed();
  }

  // Encode the data with the account's nonce for generating a signature
  function encodeWithSaltAndBorrowerCounter(
    address borrower,
    bytes32 salt,
    bytes32 caveatHash
  ) public view virtual returns (bytes memory) {
    return
      abi.encodePacked(
        bytes1(0x19),
        bytes1(0x01),
        _DOMAIN_SEPARATOR,
        keccak256(
          abi.encode(
            INTENT_ORIGINATION_TYPEHASH,
            salt,
            borrowerNonce[borrower],
            caveatHash
          )
        )
      );
  }

  function name() public pure override returns (string memory) {
    return "Astaria Loan Manager";
  }

  function symbol() public pure override returns (string memory) {
    return "ALM";
  }

  // MODIFIERS
  modifier onlySeaport() {
    if (msg.sender != address(seaport)) {
      revert InvalidSender();
    }
    _;
  }

  // function active(Loan calldata loan) public view returns (bool) {
  //   return
  //     _getExtraData(uint256(keccak256(abi.encode(loan)))) ==
  //     uint8(FieldFlags.ACTIVE);
  // }

  function active(uint256 loanId) public view returns (bool) {
    return _getExtraData(loanId) == uint8(FieldFlags.ACTIVE);
  }

  function inactive(uint256 loanId) public view returns (bool) {
    return _getExtraData(loanId) == uint8(FieldFlags.INACTIVE);
  }

  function initialized(uint256 loanId) public view returns (bool) {
    return _getExtraData(loanId) == uint8(FieldFlags.INITIALIZED);
  }

  function tokenURI(
    uint256 tokenId
  ) public view override returns (string memory) {
    return string(abi.encodePacked("https://astaria.xyz/loans?id=", tokenId));
  }

  function _issued(uint256 tokenId) internal view returns (bool) {
    return (_getExtraData(tokenId) > uint8(0));
  }

  function issued(uint256 tokenId) external view returns (bool) {
    return _issued(tokenId);
  }

  //  function getIssuer(
  //    Loan calldata loan
  //  ) external view returns (address payable) {
  //    uint256 loanId = uint256(keccak256(abi.encode(loan)));
  //    if (!_issued(loanId)) {
  //      revert InvalidLoan(loanId);
  //    }
  //    return !_exists(loanId) ? payable(loan.issuer) : payable(_ownerOf(loanId));
  //  }

  //break the revert of the ownerOf method, so we can ensure anyone calling it in the settlement pipeline wont halt
  function ownerOf(uint256 loanId) public view override returns (address) {
    //not hasn't been issued but exists if we own it
    return
      _issued(loanId) && !_exists(loanId) ? address(this) : _ownerOf(loanId);
  }

  function settle(Loan memory loan) external {
    if (msg.sender != loan.custodian) {
      revert InvalidSender();
    }
    _settle(loan);
  }

  function _settle(Loan memory loan) internal {
    uint256 tokenId = loan.getId();
    if (!_issued(tokenId)) {
      revert InvalidLoan(tokenId);
    }
    if (_exists(tokenId)) {
      _burn(tokenId);
    }
    _setExtraData(tokenId, uint8(FieldFlags.INACTIVE));
    emit Close(tokenId);
  }

  function _callCustody(
    ReceivedItem[] calldata consideration,
    bytes32[] calldata orderHashes,
    uint256 contractNonce,
    bytes calldata context
  ) internal returns (bytes4 selector) {
    address custodian;

    assembly {
      custodian := calldataload(add(context.offset, 0x20)) // 0x20 offset for the first address 'custodian'
    }
    // Comparing the retrieved code hash with a known hash (placeholder here)

    bytes32 codeHash;
    assembly {
      codeHash := extcodehash(custodian)
    }
    if (codeHash != DEFAULT_CUSTODIAN_CODE_HASH) {
      if (
        Custodian(custodian).custody(
          consideration,
          orderHashes,
          contractNonce,
          context
        ) != Custodian.custody.selector
      ) {
        revert InvalidAction();
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
    LoanManager.Obligation memory obligation = abi.decode(
      context,
      (LoanManager.Obligation)
    );
    consideration = maximumSpent.toReceivedItems(obligation.custodian);
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

  function _fillObligationAndVerify(
    address fulfiller,
    LoanManager.Obligation memory obligation,
    SpentItem[] calldata maximumSpentFromBorrower
  ) internal returns (SpentItem[] memory offer) {
    address receiver = obligation.borrower;
    bool enforceCaveats = fulfiller != receiver ||
      obligation.caveats.length > 0;
    if (enforceCaveats) {
      receiver = address(this);
    }
    Originator.Response memory response = Originator(obligation.originator)
      .execute(
        Originator.Request({
          custodian: obligation.custodian,
          receiver: receiver,
          collateral: maximumSpentFromBorrower,
          debt: obligation.debt,
          details: obligation.details,
          signature: obligation.signature
        })
      );
    Loan memory loan = Loan({
      start: block.timestamp,
      issuer: response.issuer,
      custodian: obligation.custodian,
      borrower: obligation.borrower,
      originator: obligation.originator,
      collateral: maximumSpentFromBorrower,
      debt: obligation.debt,
      terms: response.terms
    });
    // we settle via seaport channels if caveats are present
    if (enforceCaveats) {
      bytes32 caveatHash = keccak256(
        encodeWithSaltAndBorrowerCounter(
          obligation.borrower,
          obligation.salt,
          keccak256(abi.encode(obligation.caveats))
        )
      );
      //prevent replay on the hash
      usedHashes[caveatHash] = true;
      uint256 i = 0;
      for (; i < obligation.caveats.length; ) {
        if (
          !CaveatEnforcer(obligation.caveats[i].enforcer).enforceCaveat(
            obligation.caveats[i].terms,
            loan
          )
        ) {
          revert InvalidOrigination();
        }
        unchecked {
          ++i;
        }
      }
      offer = _setOffer(loan.debt, caveatHash);
    }

    _issueLoanManager(loan, response.issuer.code.length > 0);
  }

  function _issueLoanManager(Loan memory loan, bool mint) internal {
    bytes memory encodedLoan = abi.encode(loan);

    uint256 loanId = loan.getId();

    _setExtraData(loanId, uint8(FieldFlags.ACTIVE));
    if (mint) {
      _safeMint(loan.issuer, loanId, encodedLoan);
    }
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
    LoanManager.Obligation memory obligation = abi.decode(
      context,
      (LoanManager.Obligation)
    );
    consideration = maximumSpent.toReceivedItems(obligation.custodian);

    if (obligation.debt.length == 0) {
      revert InvalidDebtEmpty();
    }

    if (maximumSpent.length == 0) {
      revert InvalidMaximumSpentEmpty();
    }
    offer = _fillObligationAndVerify(fulfiller, obligation, maximumSpent);
  }

  function _setDebtApprovals(SpentItem memory debt) internal {
    //approve consideration based on item type
    if (debt.itemType != ItemType.ERC20) {
      ERC721(debt.token).setApprovalForAll(address(seaport), true);
    } else {
      ERC20(debt.token).approve(address(seaport), debt.amount);
    }
  }

  function _setOffer(
    SpentItem[] memory debt,
    bytes32 caveatHash
  ) internal returns (SpentItem[] memory offer) {
    offer = new SpentItem[](debt.length + 1);
    offer[0] = SpentItem({
      itemType: ItemType.ERC721,
      token: address(this),
      identifier: uint256(caveatHash),
      amount: 1
    });
    uint256 i = 0;
    for (; i < debt.length; ) {
      offer[i + 1] = debt[i];
      _setDebtApprovals(debt[i]);
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
    //active loans do nothing
    if (from != address(this)) revert("cannot transfer loans");
  }

  function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId,
    bytes calldata data
  ) public payable override {
    if (from != address(this)) revert("Cannot transfer loans");
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
    _callCustody(consideration, orderHashes, contractNonce, context);
    ratifyOrderMagicValue = ContractOffererInterface.ratifyOrder.selector;
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

  //TODO: needs tests
  function refinance(
    LoanManager.Loan memory loan,
    bytes memory newPricingData,
    address conduit
  ) external {
    (, , address conduitController) = seaport.information();
    if (
      ConduitControllerInterface(conduitController).ownerOf(conduit) !=
      msg.sender
    ) {
      revert InvalidConduit();
    }
    (
      // used to update the new loan amount
      ReceivedItem[] memory considerationPayment,
      // used to pay the carry amount
      ReceivedItem[] memory carryPayment,
      // note: considerationPayment - carryPayment = amount to pay lender

      // used for any additional payments beyond consideration and carry
      ReceivedItem[] memory additionalPayment
    ) = Pricing(loan.terms.pricing).isValidRefinance(loan, newPricingData);

    ReceivedItem[] memory refinanceConsideration = _mergeConsiderations(
      considerationPayment,
      carryPayment,
      additionalPayment
    );
    refinanceConsideration = _removeZeroAmounts(refinanceConsideration);

    // if for malicious or non-malicious the refinanceConsideration is zero
    if (refinanceConsideration.length == 0)
      revert InvalidNoRefinanceConsideration();
    _settle(loan);
    uint256 i = 0;
    for (; i < loan.debt.length; ) {
      loan.debt[i].amount = considerationPayment[i].amount;
      unchecked {
        ++i;
      }
    }
    if (
      ConduitInterface(conduit).execute(
        _packageTransfers(refinanceConsideration, msg.sender)
      ) != ConduitInterface.execute.selector
    ) {
      revert ConduitTransferError();
    }

    loan.terms.pricingData = newPricingData;
    loan.originator = msg.sender;
    loan.issuer = msg.sender;
    loan.start = block.timestamp;
    _issueLoanManager(loan, msg.sender.code.length > 0);
  }
}
