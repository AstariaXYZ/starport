// SPDX-License-Identifier: BUSL-1.1
/**
 *                                                                                                                           ,--,
 *                                                                                                                        ,---.'|
 *      ,----..    ,---,                                                                            ,-.                   |   | :
 *     /   /   \ ,--.' |                  ,--,                                                  ,--/ /|                   :   : |                 ,---,
 *    |   :     :|  |  :                ,--.'|         ,---,          .---.   ,---.    __  ,-.,--. :/ |                   |   ' :               ,---.'|
 *    .   |  ;. /:  :  :                |  |,      ,-+-. /  |        /. ./|  '   ,'\ ,' ,'/ /|:  : ' /  .--.--.           ;   ; '               |   | :     .--.--.
 *    .   ; /--` :  |  |,--.  ,--.--.   `--'_     ,--.'|'   |     .-'-. ' | /   /   |'  | |' ||  '  /  /  /    '          '   | |__   ,--.--.   :   : :    /  /    '
 *    ;   | ;    |  :  '   | /       \  ,' ,'|   |   |  ,"' |    /___/ \: |.   ; ,. :|  |   ,''  |  : |  :  /`./          |   | :.'| /       \  :     |,-.|  :  /`./
 *    |   : |    |  |   /' :.--.  .-. | '  | |   |   | /  | | .-'.. '   ' .'   | |: :'  :  /  |  |   \|  :  ;_            '   :    ;.--.  .-. | |   : '  ||  :  ;_
 *    .   | '___ '  :  | | | \__\/: . . |  | :   |   | |  | |/___/ \:     ''   | .; :|  | '   '  : |. \\  \    `.         |   |  ./  \__\/: . . |   |  / : \  \    `.
 *    '   ; : .'||  |  ' | : ," .--.; | '  : |__ |   | |  |/ .   \  ' .\   |   :    |;  : |   |  | ' \ \`----.   \        ;   : ;    ," .--.; | '   : |: |  `----.   \
 *    '   | '/  :|  :  :_:,'/  /  ,.  | |  | '.'||   | |--'   \   \   ' \ | \   \  / |  , ;   '  : |--'/  /`--'  /        |   ,/    /  /  ,.  | |   | '/ : /  /`--'  /
 *    |   :    / |  | ,'   ;  :   .'   \;  :    ;|   |/        \   \  |--"   `----'   ---'    ;  |,'  '--'.     /         '---'    ;  :   .'   \|   :    |'--'.     /
 *     \   \ .'  `--''     |  ,     .-./|  ,   / '---'          \   \ |                       '--'      `--'---'                   |  ,     .-.//    \  /   `--'---'
 *      `---`               `--`---'     ---`-'                  '---"                                                              `--`---'    `-'----'
 *
 * Chainworks Labs
 */
pragma solidity ^0.8.17;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ItemType, OfferItem, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Pricing} from "./pricing/Pricing.sol";
import {StarportLib, AdditionalTransfer} from "./lib/StarportLib.sol";
import {Custodian} from "./Custodian.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {CaveatEnforcer} from "./enforcers/CaveatEnforcer.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {PausableNonReentrant} from "./lib/PausableNonReentrant.sol";
import {Settlement} from "./settlement/Settlement.sol";

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
        address status; //the address of the status module
        bytes statusData; //bytes encoded hook data
        address pricing; //the address o the pricing module
        bytes pricingData; //bytes encoded pricing data
        address settlement; //the address of the handler module
        bytes settlementData; //bytes encoded handler data
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

    struct Fee {
        bool enabled;
        uint88 amount;
    }

    bytes32 internal immutable _DOMAIN_SEPARATOR;

    ConsiderationInterface public immutable seaport;

    address payable public immutable defaultCustodian;
    bytes32 public immutable DEFAULT_CUSTODIAN_CODE_HASH;

    // Define the EIP712 domain and typehash constants for generating signatures
    bytes32 public constant EIP_DOMAIN =
        keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant INTENT_ORIGINATION_TYPEHASH =
        keccak256("Origination(bytes32 hash,bytes32 salt,bytes32 caveatHash");
    bytes32 public constant VERSION = keccak256("0");
    mapping(uint256 => FieldFlags) public loanState;

    mapping(address => mapping(bytes32 => bool)) public invalidHashes;
    mapping(address => mapping(address => ApprovalType)) public approvals;
    mapping(address => uint256) public caveatNonces;
    mapping(address => Fee) public feeOverrides;
    address public feeTo;
    uint88 public defaultFeeRake;

    event Close(uint256 loanId);
    event Open(uint256 loanId, Starport.Loan loan);
    event CaveatNonceIncremented(uint256 newNonce);
    event CaveatSaltInvalidated(bytes32 invalidatedSalt);
    event FeeDataUpdated(address feeTo, uint88 defaultFeeRake);
    event FeeOverrideUpdated(address token, uint88 overrideValue, bool enabled);
    event ApprovalSet(address indexed owner, address indexed spender, ApprovalType approvalType);

    error InvalidRefinance();
    error InvalidCustodian();
    error InvalidLoan();
    error CannotTransferLoans();
    error AdditionalTransferError();
    error LoanExists();
    error NotLoanCustodian();
    error NotSeaport();
    error NativeAssetsNotSupported();
    error UnauthorizedAdditionalTransferIncluded();
    error InvalidCaveatSigner();
    error MalformedRefinance();
    error InvalidPostRepayment();

    constructor(ConsiderationInterface seaport_) {
        address custodian = address(new Custodian(this, seaport_));
        seaport = seaport_;

        bytes32 defaultCustodianCodeHash;
        assembly {
            defaultCustodianCodeHash := extcodehash(custodian)
        }
        defaultCustodian = payable(custodian);
        DEFAULT_CUSTODIAN_CODE_HASH = defaultCustodianCodeHash;
        _DOMAIN_SEPARATOR = keccak256(abi.encode(EIP_DOMAIN, VERSION, block.chainid, address(this)));
        _initializeOwner(msg.sender);
    }

    /*
    * @dev set's approval to originate loans without having to check caveats
    * @param who                The address of who is being approved
    * @param approvalType       The type of approval (Borrower, Lender) (cant be both)
    */
    function setOriginateApproval(address who, ApprovalType approvalType) external {
        approvals[msg.sender][who] = approvalType;
        emit ApprovalSet(msg.sender, who, approvalType);
    }

    /*
    * @dev loan origination method, new loan data is passed in and validated before being issued
    * @param additionalTransfers     Additional transfers to be made after the loan is issued
    * @param borrowerCaveat          The borrower caveat to be validated
    * @param lenderCaveat            The lender caveat to be validated
    * @param loan                    The loan to be issued
    */
    function originate(
        AdditionalTransfer[] calldata additionalTransfers,
        CaveatEnforcer.CaveatWithApproval calldata borrowerCaveat,
        CaveatEnforcer.CaveatWithApproval calldata lenderCaveat,
        Starport.Loan memory loan
    ) external payable pausableNonReentrant {
        //cache the addresses
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

        //sets originator and start time
        _issueLoan(loan);
        _callCustody(loan);
    }

    /*
    * @dev refinances an existing loan with new pricing data
    * its the only thing that can be changed
    * @param lender                  The new lender
    * @param lenderCaveat            The lender caveat to be validated
    * @param loan                    The loan to be issued
    * @param newPricingData          The new pricing data
    */
    function refinance(
        address lender,
        CaveatEnforcer.CaveatWithApproval calldata lenderCaveat,
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

        //sets originator and start time
        _issueLoan(loan);
    }

    /**
     * @dev settle the loan with the LoanManager
     *
     * @param loan              The the loan that is settled
     * @param fulfiller      The address executing seaport
     */
    function _postRepaymentExecute(Starport.Loan memory loan, address fulfiller) internal virtual {
        if (Settlement(loan.terms.settlement).postRepayment(loan, fulfiller) != Settlement.postRepayment.selector) {
            revert InvalidPostRepayment();
        }
    }

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
     * @dev  internal method to call the custody selector of the custodian if it does not share
     * the same codehash as the default custodian
     * @param loan                  The loan being placed into custody
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
            ) revert UnauthorizedAdditionalTransferIncluded();
            unchecked {
                ++i;
            }
        }
    }

    function _validateAndEnforceCaveats(
        CaveatEnforcer.CaveatWithApproval calldata caveatApproval,
        address validator,
        AdditionalTransfer[] memory additionalTransfers,
        Starport.Loan memory loan
    ) internal {
        bytes32 hash = hashCaveatWithSaltAndNonce(validator, caveatApproval.salt, caveatApproval.caveat);
        invalidHashes.validateSalt(validator, caveatApproval.salt);

        if (
            !SignatureCheckerLib.isValidSignatureNow(
                validator, hash, caveatApproval.v, caveatApproval.r, caveatApproval.s
            )
        ) {
            revert InvalidCaveatSigner();
        }

        for (uint256 i = 0; i < caveatApproval.caveat.length;) {
            CaveatEnforcer(caveatApproval.caveat[i].enforcer).validate(
                additionalTransfers, loan, caveatApproval.caveat[i].data
            );
            unchecked {
                ++i;
            }
        }
    }

    function hashCaveatWithSaltAndNonce(address validator, bytes32 salt, CaveatEnforcer.Caveat[] calldata caveat)
        public
        view
        virtual
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                _DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        INTENT_ORIGINATION_TYPEHASH, caveatNonces[validator], salt, keccak256(abi.encode(caveat))
                    )
                )
            )
        );
    }

    function incrementCaveatNonce() external {
        uint256 newNonce = caveatNonces[msg.sender] + uint256(blockhash(block.number - 1) << 0x80);
        caveatNonces[msg.sender] = newNonce;
        emit CaveatNonceIncremented(newNonce);
    }

    function invalidateCaveatSalt(bytes32 salt) external {
        invalidHashes[msg.sender][salt] = true;
        emit CaveatSaltInvalidated(salt);
    }

    /**
     * @dev  helper to check if a loan is active
     * @param loanId            The id of the loan
     * @return                  True if the loan is active
     */
    function active(uint256 loanId) public view returns (bool) {
        return loanState[loanId] == FieldFlags.ACTIVE;
    }

    /**
     * @dev  helper to check if a loan is inactive
     * @param loanId            The id of the loan
     * @return                  True if the loan is inactive
     */
    function inactive(uint256 loanId) public view returns (bool) {
        return loanState[loanId] == FieldFlags.INACTIVE;
    }

    /**
     * @dev  helper to check if a loan is initialized(ie. has never been opened)
     * guarded to ensure only the loan.custodian can call it
     * @param loan              The entire loan struct
     */
    function settle(Loan memory loan) external {
        if (msg.sender != loan.custodian) {
            revert NotLoanCustodian();
        }
        _settle(loan);
    }

    function _settle(Loan memory loan) internal {
        uint256 loanId = loan.getId();
        if (inactive(loanId)) {
            revert InvalidLoan();
        }

        loanState[loanId] = FieldFlags.INACTIVE;
        emit Close(loanId);
    }

    /**
     * @dev set's the default fee Data
     * only owner can call
     * @param feeTo_  The feeToAddress
     * @param defaultFeeRake_ the default fee rake in WAD denomination(1e17 = 10%)
     */
    function setFeeData(address feeTo_, uint88 defaultFeeRake_) external onlyOwner {
        feeTo = feeTo_;
        defaultFeeRake = defaultFeeRake_;
        emit FeeDataUpdated(feeTo_, defaultFeeRake_);
    }

    /**
     * @dev set's fee override's for specific tokens
     * only owner can call
     * @param token             The token to override
     * @param overrideValue     The new value in WAD denomination to override(1e17 = 10%)
     * @param enabled           Whether or not the override is enabled
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
            if (debt[i].itemType == ItemType.ERC20) {
                Fee memory feeOverride = feeOverrides[debt[i].token];
                feeItems[i].identifier = 0;
                uint256 amount = debt[i].amount.mulDiv(
                    !feeOverride.enabled ? defaultFeeRake : feeOverride.amount, 10 ** ERC20(debt[i].token).decimals()
                );
                paymentToBorrower[i] = SpentItem({
                    token: debt[i].token,
                    itemType: debt[i].itemType,
                    identifier: debt[i].identifier,
                    amount: debt[i].amount - amount
                });
                if (amount > 0) {
                    feeItems[i].amount = amount;
                    feeItems[i].token = debt[i].token;
                    feeItems[i].itemType = debt[i].itemType;

                    ++totalFeeItems;
                }
            }
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(feeItems, totalFeeItems)
        }
    }

    /**
     * @dev issues a LM token if needed
     * only owner can call
     * @param loan  the loan to issue
     */
    function _issueLoan(Loan memory loan) internal {
        loan.start = block.timestamp;
        loan.originator = msg.sender;

        bytes memory encodedLoan = abi.encode(loan);

        uint256 loanId = loan.getId();
        if (active(loanId)) {
            revert LoanExists();
        }

        loanState[loanId] = FieldFlags.ACTIVE;
        if (loan.issuer.code.length > 0) {
            loan.issuer.call(abi.encodeWithSelector(LoanOpened.onLoanOpened.selector, loan));
        }
        emit Open(loanId, loan);
    }
}

interface LoanOpened {
    function onLoanOpened(Starport.Loan memory loan) external;
}
