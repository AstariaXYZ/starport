// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

pragma solidity ^0.8.17;

import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {Custodian} from "starport-core/Custodian.sol";
import {PausableNonReentrant} from "starport-core/lib/PausableNonReentrant.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {Settlement} from "starport-core/settlement/Settlement.sol";
import {StarportLib, AdditionalTransfer} from "starport-core/lib/StarportLib.sol";

import {SpentItem, ItemType} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";

contract Starport is PausableNonReentrant {
    using FixedPointMathLib for uint256;
    using {StarportLib.getId} for Starport.Loan;
    using {StarportLib.validateSalt} for mapping(address => mapping(bytes32 => bool));

    enum ApprovalType {
        NOTHING,
        BORROWER,
        LENDER
    }
    enum FieldFlags {
        INACTIVE,
        ACTIVE
    }

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

    struct Fee {
        bool enabled;
        uint88 amount;
    }

    bytes32 internal immutable _DOMAIN_SEPARATOR;

    address public immutable defaultCustodian;
    bytes32 public immutable DEFAULT_CUSTODIAN_CODE_HASH;

    // Define the EIP712 domain and typehash constants for generating signatures
    bytes32 public constant EIP_DOMAIN =
        keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
    string public constant VERSION = "0";
    bytes32 public constant INTENT_ORIGINATION_TYPEHASH = keccak256(
        "Origination(address account,uint256 accountNonce,bool singleUse,bytes32 salt,uint256 deadline,bytes32 caveatHash"
    );

    address public feeTo;
    uint88 public defaultFeeRake;

    mapping(address => Fee) public feeOverrides;
    mapping(address => mapping(address => ApprovalType)) public approvals;
    mapping(address => mapping(bytes32 => bool)) public invalidSalts;
    mapping(address => uint256) public caveatNonces;
    mapping(uint256 => uint256) public loanState;

    event ApprovalSet(address indexed owner, address indexed spender, uint8 approvalType);
    event CaveatFilled(address owner, bytes32 hash, bytes32 salt);
    event CaveatNonceIncremented(address owner, uint256 newNonce);
    event CaveatSaltInvalidated(address owner, bytes32 salt);
    event Close(uint256 loanId);
    event FeeDataUpdated(address feeTo, uint88 defaultFeeRake);
    event FeeOverrideUpdated(address token, uint88 overrideValue, bool enabled);
    event Open(uint256 loanId, Starport.Loan loan);

    error AdditionalTransferError();
    error CannotTransferLoans();
    error CaveatDeadlineExpired();
    error InvalidCaveatSigner();
    error InvalidCustodian();
    error InvalidLoan();
    error InvalidPostRepayment();
    error InvalidRefinance();
    error LoanExists();
    error MalformedRefinance();
    error NotLoanCustodian();
    error UnauthorizedAdditionalTransferIncluded();

    constructor(address seaport_) {
        address custodian = address(new Custodian(this, seaport_));

        bytes32 defaultCustodianCodeHash;
        assembly {
            defaultCustodianCodeHash := extcodehash(custodian)
        }
        defaultCustodian = payable(custodian);
        DEFAULT_CUSTODIAN_CODE_HASH = defaultCustodianCodeHash;
        _DOMAIN_SEPARATOR = keccak256(abi.encode(EIP_DOMAIN, VERSION, block.chainid, address(this)));
        _initializeOwner(msg.sender);
    }

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
        bytes calldata pricingData
    ) external pausableNonReentrant {
        if (loan.start == block.timestamp) {
            revert InvalidLoan();
        }
        (
            SpentItem[] memory considerationPayment,
            SpentItem[] memory carryPayment,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).getRefinanceConsideration(loan, pricingData, msg.sender);

        _settle(loan);
        _postRepaymentExecute(loan, msg.sender);
        loan = applyRefinanceConsiderationToLoan(loan, considerationPayment, carryPayment, pricingData);

        StarportLib.transferSpentItems(considerationPayment, lender, loan.issuer, false);
        if (carryPayment.length > 0) {
            StarportLib.transferSpentItems(carryPayment, lender, loan.originator, false);
        }

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
     * @dev Settle the loan with the LoanManager
     * @param loan The the loan that is settled
     * @param fulfiller The address executing the settle
     */
    function _postRepaymentExecute(Starport.Loan memory loan, address fulfiller) internal virtual {
        if (Settlement(loan.terms.settlement).postRepayment(loan, fulfiller) != Settlement.postRepayment.selector) {
            revert InvalidPostRepayment();
        }
    }

    /**
     * @dev Refinances an existing loan with new pricing data, its the only thing that can be changed
     * @param loan The target loan
     * @param considerationPayment the payment consideration
     * @param carryPayment The loan to be issued
     * @param pricingData The new pricing data
     */
    function applyRefinanceConsiderationToLoan(
        Starport.Loan memory loan,
        SpentItem[] memory considerationPayment,
        SpentItem[] memory carryPayment,
        bytes calldata pricingData
    ) public pure returns (Starport.Loan memory) {
        if (
            considerationPayment.length == 0
                || (carryPayment.length != 0 && considerationPayment.length != carryPayment.length)
                || considerationPayment.length != loan.debt.length
        ) {
            revert MalformedRefinance();
        }

        uint256 i = 0;
        if (carryPayment.length > 0) {
            for (; i < considerationPayment.length;) {
                loan.debt[i].amount = considerationPayment[i].amount + carryPayment[i].amount;

                unchecked {
                    ++i;
                }
            }
        } else {
            for (; i < considerationPayment.length;) {
                loan.debt[i].amount = considerationPayment[i].amount;
                unchecked {
                    ++i;
                }
            }
        }
        loan.terms.pricingData = pricingData;
        return loan;
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
        assembly {
            codeHash := extcodehash(custodian)
        }
        if (
            codeHash != DEFAULT_CUSTODIAN_CODE_HASH
                && Custodian(payable(custodian)).custody(loan) != Custodian.custody.selector
        ) {
            revert InvalidCustodian();
        }
    }

    /**
     * @dev Internal method to validate additional transfers
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
            if (additionalTransfers[i].from != lender && additionalTransfers[i].from != fulfiller) {
                revert UnauthorizedAdditionalTransferIncluded();
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Internal method to validate additional transfers
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
            if (
                additionalTransfers[i].from != borrower && additionalTransfers[i].from != lender
                    && additionalTransfers[i].from != fulfiller
            ) {
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
            invalidSalts.validateSalt(validator, signedCaveats.salt);
            emit CaveatFilled(validator, hash, signedCaveats.salt);
        }

        if (block.timestamp > signedCaveats.deadline) {
            revert CaveatDeadlineExpired();
        }
        if (!SignatureCheckerLib.isValidSignatureNowCalldata(validator, hash, signedCaveats.signature)) {
            revert InvalidCaveatSigner();
        }

        for (uint256 i = 0; i < signedCaveats.caveats.length;) {
            CaveatEnforcer(signedCaveats.caveats[i].enforcer).validate(
                additionalTransfers, loan, signedCaveats.caveats[i].data
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Helper to hash a caveat with a salt and nonce
     * @param account The account that is originating the loan
     * @param singleUse Whether or not the caveat is single use
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
        return keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                _DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        INTENT_ORIGINATION_TYPEHASH,
                        account,
                        caveatNonces[account],
                        singleUse,
                        salt,
                        deadline,
                        keccak256(abi.encode(caveats))
                    )
                )
            )
        );
    }

    /**
     * @dev Increments caveat nonce for sender and emits event
     */
    function incrementCaveatNonce() external {
        uint256 newNonce = caveatNonces[msg.sender] + uint256(blockhash(block.number - 1) << 0x80);
        caveatNonces[msg.sender] = newNonce;
        emit CaveatNonceIncremented(msg.sender, newNonce);
    }

    /**
     * @dev Invalidates a caveat salt
     * @param salt The salt to invalidate
     */
    function invalidateCaveatSalt(bytes32 salt) external {
        invalidSalts[msg.sender][salt] = true;
        emit CaveatSaltInvalidated(msg.sender, salt);
    }

    /**
     * @dev Helper to check if a loan is active
     * @param loanId The id of the loan
     * @return bool True if the loan is active
     */
    function active(uint256 loanId) public view returns (bool) {
        return loanState[loanId] == uint256(FieldFlags.ACTIVE);
    }

    /**
     * @dev Helper to check if a loan is inactive
     * @param loanId The id of the loan
     * @return bool True if the loan is inactive
     */
    function inactive(uint256 loanId) public view returns (bool) {
        return loanState[loanId] == uint256(FieldFlags.INACTIVE);
    }

    /**
     * @dev Helper to check if a loan is initialized(ie. has never been opened)
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
     * @dev Internal helper to check if a loan is initialized
     * @param loan The entire loan struct
     */
    function _settle(Loan memory loan) internal {
        uint256 loanId = loan.getId();
        if (inactive(loanId)) {
            revert InvalidLoan();
        }

        loanState[loanId] = uint256(FieldFlags.INACTIVE);

        emit Close(loanId);
    }

    /**
     * @dev Sets the default fee data, only owner can call
     * @param feeTo_ The feeToAddress
     * @param defaultFeeRake_ The default fee rake in WAD denomination(1e17 = 10%)
     */
    function setFeeData(address feeTo_, uint88 defaultFeeRake_) external onlyOwner {
        feeTo = feeTo_;
        defaultFeeRake = defaultFeeRake_;
        emit FeeDataUpdated(feeTo_, defaultFeeRake_);
    }

    /**
     * @dev set's fee override's for specific tokens
     * only owner can call
     * @param token The token to override
     * @param overrideValue The new value in WAD denomination to override(1e17 = 10%)
     * @param enabled Whether or not the override is enabled
     */
    function setFeeOverride(address token, uint88 overrideValue, bool enabled) external onlyOwner {
        feeOverrides[token] = Fee({enabled: enabled, amount: overrideValue});
        emit FeeOverrideUpdated(token, overrideValue, enabled);
    }

    /**
     * @dev set's fee override's for specific tokens
     * only owner can call
     * @param debt The debt to rake
     * @return feeItems SpentItem[] of fee's
     */
    function _feeRake(SpentItem[] memory debt)
        internal
        view
        returns (SpentItem[] memory feeItems, SpentItem[] memory paymentToBorrower)
    {
        feeItems = new SpentItem[](debt.length);
        paymentToBorrower = new SpentItem[](debt.length);
        uint256 totalFeeItems;
        for (uint256 i = 0; i < debt.length;) {
            uint256 amount;
            if (debt[i].itemType == ItemType.ERC20) {
                Fee memory feeOverride = feeOverrides[debt[i].token];
                feeItems[i].identifier = 0;
                amount = debt[i].amount.mulDiv(
                    !feeOverride.enabled ? defaultFeeRake : feeOverride.amount, 10 ** ERC20(debt[i].token).decimals()
                );

                if (amount > 0) {
                    feeItems[i].amount = amount;
                    feeItems[i].token = debt[i].token;
                    feeItems[i].itemType = debt[i].itemType;

                    ++totalFeeItems;
                }
            }
            paymentToBorrower[i] = SpentItem({
                token: debt[i].token,
                itemType: debt[i].itemType,
                identifier: debt[i].identifier,
                amount: debt[i].amount - amount
            });
            unchecked {
                ++i;
            }
        }

        assembly {
            mstore(feeItems, totalFeeItems)
        }
    }

    /**
     * @dev issues a LM token if needed, only owner can call
     * @param loan  the loan to issue
     */
    function _issueLoan(Loan memory loan) internal {
        loan.start = block.timestamp;
        loan.originator = loan.originator != address(0) ? loan.originator : msg.sender;

        bytes memory encodedLoan = abi.encode(loan);

        uint256 loanId = loan.getId();
        if (active(loanId)) {
            revert LoanExists();
        }

        loanState[loanId] = uint256(FieldFlags.ACTIVE);
        emit Open(loanId, loan);
    }
}
