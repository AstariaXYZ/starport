// SPDX-License-Identifier: BUSL-1.1
//
//                       ↑↑↑↑                 ↑↑
//                       ↑↑↑↑                ↑↑↑↑↑
//                       ↑↑↑↑              ↑   ↑
//                       ↑↑↑↑            ↑↑↑↑↑
//            ↑          ↑↑↑↑          ↑   ↑
//          ↑↑↑↑↑        ↑↑↑↑        ↑↑↑↑↑
//            ↑↑↑↑↑      ↑↑↑↑      ↑↑↑↑↑                                   ↑↑↑                                                                      ↑↑↑
//              ↑↑↑↑↑    ↑↑↑↑    ↑↑↑↑↑                          ↑↑↑        ↑↑↑         ↑↑↑            ↑↑         ↑↑            ↑↑↑            ↑↑    ↑↑↑
//                ↑↑↑↑↑  ↑↑↑↑  ↑↑↑↑↑                         ↑↑↑↑ ↑↑↑↑   ↑↑↑↑↑↑↑    ↑↑↑↑↑↑↑↑↑     ↑↑ ↑↑↑   ↑↑↑↑↑↑↑↑↑↑↑     ↑↑↑↑↑↑↑↑↑↑    ↑↑↑ ↑↑↑  ↑↑↑↑↑↑↑
//                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑                           ↑↑     ↑↑↑    ↑↑↑     ↑↑↑     ↑↑↑    ↑↑↑      ↑↑↑      ↑↑↑   ↑↑↑      ↑↑↑   ↑↑↑↑       ↑↑↑
//                    ↑↑↑↑↑↑↑↑↑↑                             ↑↑↑↑↑         ↑↑↑            ↑↑↑↑    ↑↑       ↑↑↑       ↑↑   ↑↑↑       ↑↑↑  ↑↑↑        ↑↑↑
//  ↑↑↑↑  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑   ↑↑↑   ↑↑↑             ↑↑↑↑↑↑↑    ↑↑↑     ↑↑↑↑↑↑  ↑↑↑    ↑↑       ↑↑↑       ↑↑↑  ↑↑↑       ↑↑↑  ↑↑↑        ↑↑↑
//  ↑↑↑↑  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑   ↑↑↑   ↑↑↑                  ↑↑    ↑↑↑     ↑↑      ↑↑↑    ↑↑       ↑↑↑      ↑↑↑   ↑↑↑      ↑↑↑   ↑↑↑        ↑↑↑
//                    ↑↑↑↑↑↑↑↑↑↑                             ↑↑↑    ↑↑↑    ↑↑↑     ↑↑↑    ↑↑↑↑    ↑↑       ↑↑↑↑↑  ↑↑↑↑     ↑↑↑↑   ↑↑↑    ↑↑↑        ↑↑↑
//                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑                             ↑↑↑↑↑↑       ↑↑↑↑     ↑↑↑↑↑ ↑↑↑    ↑↑       ↑↑↑ ↑↑↑↑↑↑        ↑↑↑↑↑↑      ↑↑↑          ↑↑↑
//                ↑↑↑↑↑  ↑↑↑↑  ↑↑↑↑↑                                                                       ↑↑↑
//              ↑↑↑↑↑    ↑↑↑↑    ↑↑↑↑                                                                      ↑↑↑     Starport: Lending Kernel
//                ↑      ↑↑↑↑     ↑↑↑↑↑
//                       ↑↑↑↑       ↑↑↑↑↑                                                                          Designed with love by Astaria Labs, Inc
//                       ↑↑↑↑         ↑
//                       ↑↑↑↑
//                       ↑↑↑↑
//                       ↑↑↑↑
//                       ↑↑↑↑

pragma solidity ^0.8.17;

import {CaveatEnforcer} from "./enforcers/CaveatEnforcer.sol";
import {Custodian} from "./Custodian.sol";
import {PausableNonReentrant} from "./lib/PausableNonReentrant.sol";
import {Pricing} from "./pricing/Pricing.sol";
import {Status} from "./status/Status.sol";
import {Settlement} from "./settlement/Settlement.sol";
import {StarportLib, AdditionalTransfer} from "./lib/StarportLib.sol";

import {SpentItem, ItemType} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";

interface Stargate {
    function getOwner(address) external returns (address);
}

contract Starport is PausableNonReentrant {
    using FixedPointMathLib for uint256;
    using {StarportLib.getId} for Starport.Loan;
    using {StarportLib.validateSalt} for mapping(address => mapping(bytes32 => bool));

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error CaveatDeadlineExpired();
    error InvalidFeeRakeBps();
    error InvalidCaveat();
    error InvalidCaveatLength();
    error InvalidCaveatSigner();
    error InvalidCustodian();
    error InvalidLoan();
    error InvalidLoanState();
    error InvalidPostRepayment();
    error LoanExists();
    error MalformedRefinance();
    error NotLoanCustodian();
    error UnauthorizedAdditionalTransferIncluded();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event ApprovalSet(address indexed owner, address indexed spender, uint8 approvalType);
    event CaveatFilled(address owner, bytes32 hash, bytes32 salt);
    event CaveatNonceIncremented(address owner, uint256 newNonce);
    event CaveatSaltInvalidated(address owner, bytes32 salt);
    event Close(uint256 loanId);
    event FeeDataUpdated(address feeTo, uint88 defaultFeeRakeBps);
    event FeeOverrideUpdated(address token, uint88 overrideBps, bool enabled);
    event Open(uint256 loanId, Starport.Loan loan);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint88 public constant MAX_FEE_RAKE_BPS = 500; // 5%
    uint88 public constant BPS_DENOMINATOR = 10_000; // 100%

    uint256 public constant LOAN_CLOSED_FLAG = 0x0;
    uint256 public constant LOAN_OPEN_FLAG = 0x1;

    bytes32 private constant _INVALID_LOAN = 0x045f33d100000000000000000000000000000000000000000000000000000000;
    bytes32 private constant _LOAN_EXISTS = 0x14ec57fc00000000000000000000000000000000000000000000000000000000;

    Stargate public immutable SG;
    uint256 public immutable chainId;
    bytes32 public immutable DEFAULT_CUSTODIAN_CODE_HASH;
    bytes32 public immutable CACHED_DOMAIN_SEPARATOR;

    // Define the EIP712 domain and typeHash constants for generating signatures
    bytes32 public constant EIP_DOMAIN =
        keccak256("EIP712Domain(" "string name," "string version," "uint256 chainId," "address verifyingContract" ")");
    bytes32 public constant VERSION = keccak256(bytes("0"));
    bytes32 public constant NAME = keccak256(bytes("Starport"));

    bytes32 public constant INTENT_ORIGINATION_TYPEHASH = keccak256(
        "Origination(" "address account," "uint256 accountNonce," "bool singleUse," "bytes32 salt," "uint256 deadline,"
        "Caveat[] caveats" ")" "Caveat(" "address enforcer," "bytes data" ")"
    );
    bytes32 public constant CAVEAT_TYPEHASH = keccak256("Caveat(" "address enforcer," "bytes data" ")");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Terms {
        address status; // the address of the status module
        bytes statusData; // bytes encoded hook data
        address pricing; // the address of the pricing module
        bytes pricingData; // bytes encoded pricing data
        address settlement; // the address of the handler module
        bytes settlementData; // bytes encoded handler data
    }

    struct Loan {
        uint256 start; // start of the loan
        address custodian; // where the collateral is being held
        address borrower; // the borrower
        address issuer; // the capital issuer/lender
        address originator; // who originated the loan
        SpentItem[] collateral; // array of collateral
        SpentItem[] debt; // array of debt
        Terms terms; // the actionable terms of the loan
    }

    struct FeeOverride {
        bool enabled;
        uint88 bpsOverride;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ENUMS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    enum ApprovalType {
        NOTHING,
        BORROWER,
        LENDER
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address public feeTo;
    uint256 public defaultFeeRakeBps;
    mapping(address => FeeOverride) public feeOverrides;
    mapping(address => mapping(address => ApprovalType)) public approvals;
    mapping(address => mapping(bytes32 => bool)) public invalidSalts;
    mapping(address => uint256) public caveatNonces;
    mapping(uint256 => uint256) public loanState;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address seaport_, Stargate stargate_, address owner_) {
        SG = stargate_;
        chainId = block.chainid;
        CACHED_DOMAIN_SEPARATOR = keccak256(abi.encode(EIP_DOMAIN, NAME, VERSION, block.chainid, address(this)));
        address custodian = address(new Custodian(this, seaport_));

        bytes32 defaultCustodianCodeHash;
        assembly ("memory-safe") {
            defaultCustodianCodeHash := extcodehash(custodian)
        }
        DEFAULT_CUSTODIAN_CODE_HASH = defaultCustodianCodeHash;
        _initializeOwner(owner_);
    }

    function domainSeparator() public view returns (bytes32) {
        //return the cached domain separator if the chainId is the same
        if (chainId == block.chainid) {
            return CACHED_DOMAIN_SEPARATOR;
        }
        return keccak256(abi.encode(EIP_DOMAIN, NAME, VERSION, block.chainid, address(this)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Sets approval to originate loans without having to check caveats
     * @param who The address of who is being approved
     * @param approvalType The type of approval (Borrower, Lender) (cant be both)
     */
    function setOriginateApproval(address who, ApprovalType approvalType) external {
        approvals[msg.sender][who] = approvalType;
        emit ApprovalSet(msg.sender, who, uint8(approvalType));
    }

    /**
     * @dev The loan origination method, new loan data is passed in and validated before being issued
     * @param additionalTransfers Additional transfers to be made after the loan is issued
     * @param borrowerCaveat The borrower caveat to be validated
     * @param lenderCaveat The lender caveat to be validated
     * @param loan The loan to be issued
     */
    function originate(
        AdditionalTransfer[] calldata additionalTransfers,
        CaveatEnforcer.SignedCaveats calldata borrowerCaveat,
        CaveatEnforcer.SignedCaveats calldata lenderCaveat,
        Starport.Loan memory loan
    ) external payable pausableNonReentrant {
        // Cache the addresses
        address borrower = loan.borrower;
        address issuer = loan.issuer;
        address feeRecipient = feeTo;

        if (msg.sender != borrower && approvals[borrower][msg.sender] != ApprovalType.BORROWER) {
            _validateAndEnforceCaveats(borrowerCaveat, borrower, additionalTransfers, loan);
        }

        if (msg.sender != issuer && approvals[issuer][msg.sender] != ApprovalType.LENDER) {
            _validateAndEnforceCaveats(lenderCaveat, issuer, additionalTransfers, loan);
        }

        StarportLib.transferSpentItems(loan.collateral, borrower, loan.custodian, true);

        if (feeRecipient == address(0)) {
            StarportLib.transferSpentItems(loan.debt, issuer, borrower, false);
        } else {
            (SpentItem[] memory feeItems, SpentItem[] memory sentToBorrower) = _feeRake(loan.debt);
            if (feeItems.length > 0) {
                StarportLib.transferSpentItems(feeItems, issuer, feeRecipient, false);
            }
            StarportLib.transferSpentItems(sentToBorrower, issuer, borrower, false);
        }

        if (additionalTransfers.length > 0) {
            _validateAdditionalTransfersOriginate(borrower, issuer, msg.sender, additionalTransfers);
            StarportLib.transferAdditionalTransfersCalldata(additionalTransfers);
        }

        // Sets originator and start time
        _issueLoan(loan);
        _callCustody(loan);
    }

    /**
     * @dev Refinances an existing loan with new pricing data, its the only thing that can be changed
     * @param lender The new lender
     * @param lenderCaveat The lender caveat to be validated
     * @param loan The loan to be issued
     * @param pricingData The new pricing data
     */
    function refinance(
        address lender,
        CaveatEnforcer.SignedCaveats calldata lenderCaveat,
        Starport.Loan memory loan,
        bytes calldata pricingData,
        bytes calldata extraData
    ) external pausableNonReentrant {
        if (loan.start == block.timestamp) {
            revert InvalidLoan();
        }
        if (!Status(loan.terms.status).isActive(loan, extraData)) {
            revert InvalidLoanState();
        }
        (
            SpentItem[] memory considerationPayment,
            SpentItem[] memory carryPayment,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).getRefinanceConsideration(loan, pricingData, msg.sender);

        _settle(loan);
        _postRepaymentExecute(loan, msg.sender);

        StarportLib.transferSpentItems(considerationPayment, lender, loan.issuer, false);
        if (carryPayment.length > 0) {
            StarportLib.transferSpentItems(carryPayment, lender, loan.originator, false);
        }
        loan.debt = applyRefinanceConsiderationToLoan(considerationPayment, carryPayment);
        loan.terms.pricingData = pricingData;

        loan.issuer = lender;
        loan.originator = address(0);
        loan.start = 0;

        if (msg.sender != lender && approvals[lender][msg.sender] != ApprovalType.LENDER) {
            _validateAndEnforceCaveats(lenderCaveat, lender, additionalTransfers, loan);
        }

        if (additionalTransfers.length > 0) {
            _validateAdditionalTransfersRefinance(lender, msg.sender, additionalTransfers);
            StarportLib.transferAdditionalTransfers(additionalTransfers);
        }

        // Sets originator and start time
        _issueLoan(loan);
    }

    /**
     * @dev Helper to settle a loan
     * guarded to ensure only the loan.custodian can call it
     * @param loan The entire loan struct
     */
    function settle(Loan memory loan) external {
        if (msg.sender != loan.custodian) {
            revert NotLoanCustodian();
        }
        _settle(loan);
    }

    /**
     * @dev Increments caveat nonce for sender and emits event
     */
    function incrementCaveatNonce() external {
        unchecked {
            uint256 newNonce = caveatNonces[msg.sender] + 1 + uint256(blockhash(block.number - 1) >> 0x80);
            caveatNonces[msg.sender] = newNonce;
            emit CaveatNonceIncremented(msg.sender, newNonce);
        }
    }

    /**
     * @dev Invalidates a caveat salt
     * @param salt The salt to invalidate
     */
    function invalidateCaveatSalt(bytes32 salt) external {
        invalidSalts.validateSalt(msg.sender, salt);
        emit CaveatSaltInvalidated(msg.sender, salt);
    }

    /**
     * @dev Sets the default fee data, only owner can call
     * @param feeTo_ The feeToAddress
     * @param defaultFeeRakeBps_ The default fee rake in basis points
     */
    function setFeeData(address feeTo_, uint88 defaultFeeRakeBps_) external onlyOwner {
        if (defaultFeeRakeBps_ > MAX_FEE_RAKE_BPS) {
            revert InvalidFeeRakeBps();
        }

        feeTo = feeTo_;
        defaultFeeRakeBps = defaultFeeRakeBps_;

        emit FeeDataUpdated(feeTo_, defaultFeeRakeBps_);
    }

    /**
     * @dev Sets fee overrides for specific tokens, only owner can call
     * @param token The token to override
     * @param bpsOverride The new basis points to override to (1 = 0.01%)
     * @param enabled Whether or not the override is enabled
     */
    function setFeeOverride(address token, uint88 bpsOverride, bool enabled) external onlyOwner {
        if (bpsOverride > MAX_FEE_RAKE_BPS) {
            revert InvalidFeeRakeBps();
        }

        feeOverrides[token] = FeeOverride({enabled: enabled, bpsOverride: bpsOverride});
        emit FeeOverrideUpdated(token, bpsOverride, enabled);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PUBLIC FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Refinances an existing loan with new pricing data, its the only thing that can be changed
     * @param considerationPayment the payment consideration
     * @param carryPayment The loan to be issued
     */
    function applyRefinanceConsiderationToLoan(SpentItem[] memory considerationPayment, SpentItem[] memory carryPayment)
        public
        pure
        returns (SpentItem[] memory newDebt)
    {
        if (
            considerationPayment.length == 0
                || (carryPayment.length != 0 && considerationPayment.length != carryPayment.length)
        ) {
            revert MalformedRefinance();
        }

        if (carryPayment.length > 0) {
            newDebt = new SpentItem[](considerationPayment.length);
            uint256 i = 0;
            for (; i < considerationPayment.length;) {
                newDebt[i] = considerationPayment[i];
                newDebt[i].amount += carryPayment[i].amount;
                if (newDebt[i].itemType == ItemType.ERC721 && newDebt[i].amount > 1) {
                    revert MalformedRefinance();
                }
                unchecked {
                    ++i;
                }
            }
            return newDebt;
        } else {
            uint256 i = 0;
            for (; i < considerationPayment.length;) {
                if (considerationPayment[i].itemType == ItemType.ERC721 && considerationPayment[i].amount > 1) {
                    revert MalformedRefinance();
                }
                unchecked {
                    ++i;
                }
            }
            return considerationPayment;
        }
    }

    /**
     * @dev Helper to hash a caveat with a salt and nonce
     * @param account The account that is originating the loan
     * @param singleUse Whether to invalidate the salt after validation
     * @param salt The salt to use
     * @param deadline The deadline of the caveat
     * @param caveats The caveats to hash
     * @return bytes32 The hash of the caveat
     */
    function hashCaveatWithSaltAndNonce(
        address account,
        bool singleUse,
        bytes32 salt,
        uint256 deadline,
        CaveatEnforcer.Caveat[] calldata caveats
    ) public view virtual returns (bytes32) {
        bytes32[] memory caveatHashes = new bytes32[](caveats.length);
        uint256 i = 0;
        for (; i < caveats.length;) {
            caveatHashes[i] = _hashCaveat(caveats[i]);
            unchecked {
                ++i;
            }
        }
        return keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                domainSeparator(),
                keccak256(
                    abi.encode(
                        INTENT_ORIGINATION_TYPEHASH,
                        account,
                        caveatNonces[account],
                        singleUse,
                        salt,
                        deadline,
                        keccak256(abi.encodePacked(caveatHashes))
                    )
                )
            )
        );
    }

    /**
     * @dev Internal view function to derive the EIP-712 hash for a caveat
     *
     * @param caveat The caveat to hash.
     *
     * @return The hash.
     */
    function _hashCaveat(CaveatEnforcer.Caveat memory caveat) internal pure returns (bytes32) {
        return keccak256(abi.encode(CAVEAT_TYPEHASH, caveat.enforcer, keccak256(caveat.data)));
    }

    /**
     * @dev Helper to check if a loan is open
     * @param loanId The id of the loan
     * @return bool True if the loan is open
     */
    function open(uint256 loanId) public view returns (bool) {
        return loanState[loanId] == LOAN_OPEN_FLAG;
    }

    /**
     * @dev Helper to check if a loan is closed
     * @param loanId The id of the loan
     * @return bool True if the loan is closed
     */
    function closed(uint256 loanId) public view returns (bool) {
        return loanState[loanId] == LOAN_CLOSED_FLAG;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Calls postRepayment hook on loan Settlement module
     * @param loan The the loan that is being refrenced
     * @param fulfiller The address executing the settle
     */
    function _postRepaymentExecute(Starport.Loan memory loan, address fulfiller) internal virtual {
        if (Settlement(loan.terms.settlement).postRepayment(loan, fulfiller) != Settlement.postRepayment.selector) {
            revert InvalidPostRepayment();
        }
    }

    /**
     * @dev Internal method to call the custody selector of the custodian if it does not share
     * the same codehash as the default custodian
     * @param loan The loan being placed into custody
     */
    function _callCustody(Starport.Loan memory loan) internal {
        address custodian = loan.custodian;
        // Comparing the retrieved code hash with a known hash
        bytes32 codeHash;
        assembly ("memory-safe") {
            codeHash := extcodehash(custodian)
        }
        if (codeHash != DEFAULT_CUSTODIAN_CODE_HASH && Custodian(custodian).custody(loan) != Custodian.custody.selector)
        {
            revert InvalidCustodian();
        }
    }

    /**
     * @dev Internal method to validate additional transfers, only transfer from lender and fullfiller are valid
     * @param lender The lender of the loan
     * @param fulfiller The fulfiller of the loan
     * @param additionalTransfers The additional transfers to validate
     */
    function _validateAdditionalTransfersRefinance(
        address lender,
        address fulfiller,
        AdditionalTransfer[] memory additionalTransfers
    ) internal pure {
        uint256 i = 0;
        for (; i < additionalTransfers.length;) {
            address from = additionalTransfers[i].from;
            if (from != lender && from != fulfiller) {
                revert UnauthorizedAdditionalTransferIncluded();
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Internal method to validate additional transfers, only transfers from borrower, lender, and fullfiller are valid
     * @param borrower The borrower of the loan
     * @param lender The lender of the loan
     * @param fulfiller The fulfiller of the loan
     * @param additionalTransfers The additional transfers to validate
     */
    function _validateAdditionalTransfersOriginate(
        address borrower,
        address lender,
        address fulfiller,
        AdditionalTransfer[] calldata additionalTransfers
    ) internal pure {
        uint256 i = 0;
        for (; i < additionalTransfers.length;) {
            address from = additionalTransfers[i].from;
            if (from != borrower && from != lender && from != fulfiller) {
                revert UnauthorizedAdditionalTransferIncluded();
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Internal method to validate and enforce caveats
     * @param signedCaveats The signed caveats to validate
     * @param validator The validator of the caveats
     * @param additionalTransfers The additional transfers to validate
     * @param loan The loan to validate
     */
    function _validateAndEnforceCaveats(
        CaveatEnforcer.SignedCaveats calldata signedCaveats,
        address validator,
        AdditionalTransfer[] memory additionalTransfers,
        Starport.Loan memory loan
    ) internal {
        bytes32 hash = hashCaveatWithSaltAndNonce(
            validator, signedCaveats.singleUse, signedCaveats.salt, signedCaveats.deadline, signedCaveats.caveats
        );

        if (signedCaveats.singleUse) {
            invalidSalts.validateSalt(validator, signedCaveats.salt); //Validates and invalidates salt
            emit CaveatFilled(validator, hash, signedCaveats.salt);
        } else if (invalidSalts[validator][signedCaveats.salt]) {
            revert StarportLib.InvalidSalt();
        }

        if (block.timestamp > signedCaveats.deadline) {
            revert CaveatDeadlineExpired();
        }
        if (!SignatureCheckerLib.isValidSignatureNowCalldata(validator, hash, signedCaveats.signature)) {
            revert InvalidCaveatSigner();
        }

        if (signedCaveats.caveats.length == 0) {
            revert InvalidCaveatLength();
        }

        for (uint256 i = 0; i < signedCaveats.caveats.length;) {
            if (
                CaveatEnforcer(signedCaveats.caveats[i].enforcer).validate(
                    additionalTransfers, loan, signedCaveats.caveats[i].data
                ) != CaveatEnforcer.validate.selector
            ) {
                revert InvalidCaveat();
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Internal helper to settle a loan
     * @param loan The entire loan struct
     */
    function _settle(Loan memory loan) internal {
        uint256 loanId = loan.getId();
        assembly {
            mstore(0x0, loanId)
            mstore(0x20, loanState.slot)

            // loanState[loanId]
            let loc := keccak256(0x0, 0x40)

            // if (inactive(loanId)) {
            if iszero(sload(loc)) {
                // revert InvalidLoan()
                mstore(0x0, _INVALID_LOAN)
                revert(0x0, 0x04)
            }

            sstore(loc, LOAN_CLOSED_FLAG)
        }

        emit Close(loanId);
    }

    /**
     * @dev Sets fee overrides for specific tokens, only owner can call
     * @param debt The debt to rake
     * @return feeItems SpentItem[] of fees
     */
    function _feeRake(SpentItem[] memory debt)
        internal
        view
        returns (SpentItem[] memory feeItems, SpentItem[] memory paymentToBorrower)
    {
        feeItems = new SpentItem[](debt.length);
        paymentToBorrower = new SpentItem[](debt.length);
        uint256 _defaultFeeRakeBps = defaultFeeRakeBps;
        uint256 totalFeeItems;
        for (uint256 i = 0; i < debt.length;) {
            uint256 amount;
            SpentItem memory debtItem = debt[i];
            if (debtItem.itemType == ItemType.ERC20) {
                FeeOverride memory feeOverride = feeOverrides[debtItem.token];
                SpentItem memory feeItem = feeItems[totalFeeItems];
                feeItem.identifier = 0;

                uint256 bps = feeOverride.enabled ? feeOverride.bpsOverride : _defaultFeeRakeBps;

                amount = debtItem.amount.mulDivUp(bps, BPS_DENOMINATOR);

                if (amount > 0) {
                    feeItem.amount = amount;
                    feeItem.token = debtItem.token;
                    feeItem.itemType = debtItem.itemType;

                    unchecked {
                        ++totalFeeItems;
                    }
                }
            }
            paymentToBorrower[i] = SpentItem({
                token: debtItem.token,
                itemType: debtItem.itemType,
                identifier: debtItem.identifier,
                amount: debtItem.amount - amount
            });
            unchecked {
                ++i;
            }
        }

        assembly ("memory-safe") {
            mstore(feeItems, totalFeeItems)
        }
    }

    function acquireTokens(SpentItem[] memory items) external {
        StarportLib.transferSpentItems(items, SG.getOwner(msg.sender), msg.sender, false);
    }

    /**
     * @dev Changes loanId status to open for the specified loan
     * @param loan The loan to issue
     */
    function _issueLoan(Loan memory loan) internal {
        loan.start = block.timestamp;
        loan.originator = loan.originator != address(0) ? loan.originator : msg.sender;

        uint256 loanId = loan.getId();

        assembly {
            mstore(0x0, loanId)
            mstore(0x20, loanState.slot)

            // loanState[loanId]
            let loc := keccak256(0x0, 0x40)
            // if (active(loanId))
            if iszero(iszero(sload(loc))) {
                // revert LoanExists()
                mstore(0x0, _LOAN_EXISTS)
                revert(0x0, 0x04)
            }

            sstore(loc, LOAN_OPEN_FLAG)
        }
        emit Open(loanId, loan);
    }
}
