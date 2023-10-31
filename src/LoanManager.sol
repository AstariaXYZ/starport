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

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";
import {ItemType, OfferItem, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";
import {SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";

import {StarPortLib, Actions} from "starport-core/lib/StarPortLib.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {Custodian} from "starport-core/Custodian.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

interface LoanSettledCallback {
    function onLoanSettled(LoanManager.Loan calldata loan) external;
}

contract LoanManager is Ownable, ERC721 {
    using FixedPointMathLib for uint256;

    using {StarPortLib.toReceivedItems} for SpentItem[];
    using {StarPortLib.getId} for LoanManager.Loan;
    using {StarPortLib.validateSalt} for mapping(address => mapping(bytes32 => bool));

    bytes32 internal immutable _DOMAIN_SEPARATOR;

    ConsiderationInterface public immutable seaport;
    //    bool public paused; //TODO:

    address payable public immutable defaultCustodian;
    bytes32 public immutable DEFAULT_CUSTODIAN_CODE_HASH;

    // Define the EIP712 domain and typehash constants for generating signatures
    bytes32 public constant EIP_DOMAIN =
        keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
    //    bytes32 public constant INTENT_ORIGINATION_TYPEHASH =
    //        keccak256("Origination(bytes32 hash,address enforcer,bytes32 salt,uint256 nonce,uint256 deadline,bytes data)");
    bytes32 public constant INTENT_ORIGINATION_TYPEHASH =
        keccak256("Origination(bytes32 hash,bytes32 salt,bytes32 caveatHash");
    bytes32 public constant VERSION = keccak256("0");
    address public feeTo;
    uint96 public defaultFeeRake;
    mapping(address => mapping(bytes32 => bool)) public invalidHashes;
    mapping(address => mapping(address => bool)) public approvals;
    mapping(address => uint256) public caveatNonces;
    //contract to token //fee rake
    mapping(address => Fee) public feeOverride;

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
        SpentItem[] debt;
        address originator;
        address borrower;
        bytes32 salt;
        Caveat[] caveats;
        bytes details;
        bytes approval;
    }

    struct Fee {
        bool enabled;
        uint96 amount;
    }

    event Close(uint256 loanId);
    event Open(uint256 loanId, LoanManager.Loan loan);

    error InvalidRefinance();
    error InvalidCustodian();
    error InvalidLoan();
    error InvalidItemAmount();
    error InvalidItemIdentifier(); //must be zero for ERC20's
    error InvalidItemTokenNoCode();
    error InvalidItemType();
    error InvalidTransferLength();
    error CannotTransferLoans();
    error ConduitTransferError();
    error LoanExists();
    error NotLoanCustodian();
    error NotSeaport();
    error NativeAssetsNotSupported();
    error UnauthorizedAdditionalTransferIncluded();
    error InvalidCaveatSigner();
    error MalformedRefinance();

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
    //
    //    function setApproval(address who, bool approved) external {
    //        assembly {
    //            // Compute the storage slot of approvals[msg.sender]
    //            let slot := keccak256(add(mul(caller(), 0x1000000000000000000000000), mload(approvals.slot)), 0x20)
    //
    //            // Compute the storage slot of approvals[msg.sender][who]
    //            slot := keccak256(add(who, slot), 0x20)
    //
    //            // Update the value at the computed storage slot
    //            sstore(slot, approved)
    //        }
    //    }

    //    function setApprovalTransient(address who) external {
    //        assembly {
    //            // Compute the storage slot of approvals[msg.sender]
    //            let slot := keccak256(add(mul(caller(), 0x1000000000000000000000000), mload(approvals.slot)), 0x20)
    //
    //            // Compute the storage slot of approvals[msg.sender][who]
    //            slot := keccak256(add(who, slot), 0x20)
    //
    //            // Update the value at the computed storage slot
    //            tstore(slot, 1)
    //        }
    //    }

    function setApproval(address who, bool approved) external {
        approvals[msg.sender][who] = approved;
    }

    function transferFrom(address from, address to, uint256 tokenId) public payable override {
        revert CannotTransferLoans();
    }

    function originate(
        ConduitTransfer[] calldata additionalTransfers,
        CaveatEnforcer.CaveatWithApproval calldata borrowerCaveat,
        CaveatEnforcer.CaveatWithApproval calldata lenderCaveat,
        LoanManager.Loan memory loan
    ) external payable {
        //cache the addresses
        address borrower = loan.borrower;
        address issuer = loan.issuer;
        address feeRecipient = feeTo;
        if (msg.sender != loan.borrower) {
            _validateAndEnforceCaveats(borrowerCaveat, borrower, additionalTransfers, loan);
        }

        if (msg.sender != issuer && !approvals[issuer][msg.sender]) {
            _validateAndEnforceCaveats(lenderCaveat, issuer, additionalTransfers, loan);
        }

        _transferSpentItems(loan.collateral, borrower, loan.custodian);

        _callCustody(loan);
        if (feeRecipient == address(0)) {
            _transferSpentItems(loan.debt, issuer, borrower);
        } else {
            (SpentItem[] memory feeItems, SpentItem[] memory sentToBorrower) = _feeRake(loan.debt);
            if (feeItems.length > 0) {
                _transferSpentItems(feeItems, issuer, feeRecipient);
            }
            _transferSpentItems(sentToBorrower, issuer, borrower);
        }

        if (additionalTransfers.length > 0) {
            _validateAdditionalTransfersCalldata(borrower, issuer, msg.sender, additionalTransfers);
            _transferConduitTransfers(additionalTransfers);
        }

        //sets originator and start time
        _issueLoanManager(loan);
    }

    function refinance(
        address lender,
        CaveatEnforcer.CaveatWithApproval calldata lenderCaveat,
        LoanManager.Loan memory loan,
        bytes calldata pricingData
    ) external {
        (
            SpentItem[] memory considerationPayment,
            SpentItem[] memory carryPayment,
            ConduitTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).isValidRefinance(loan, pricingData, msg.sender);

        _settle(loan);
        loan = applyRefinanceConsiderationToLoan(loan, considerationPayment, carryPayment, pricingData);

        _transferSpentItems(considerationPayment, lender, loan.issuer);
        _transferSpentItems(carryPayment, lender, loan.originator);

        loan.issuer = lender;
        loan.originator = address(0);
        loan.start = 0;

        if (msg.sender != loan.issuer && !approvals[loan.issuer][msg.sender]) {
            _validateAndEnforceCaveats(lenderCaveat, loan.issuer, additionalTransfers, loan);
        }

        if (additionalTransfers.length > 0) {
            _validateAdditionalTransfers(loan.borrower, loan.issuer, msg.sender, additionalTransfers);
            _transferConduitTransfers(additionalTransfers);
        }

        //sets originator and start time
        _issueLoanManager(loan);
    }

    function applyRefinanceConsiderationToLoan(
        LoanManager.Loan memory loan,
        SpentItem[] memory considerationPayment,
        SpentItem[] memory carryPayment,
        bytes memory pricingData
    ) public pure returns (LoanManager.Loan memory) {
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
    function _callCustody(LoanManager.Loan memory loan) internal {
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

    function _validateAdditionalTransfers(
        address borrower,
        address lender,
        address fulfiller,
        ConduitTransfer[] memory additionalTransfers
    ) internal pure {
        uint256 i = 0;
        for (i; i < additionalTransfers.length;) {
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

    function _validateAdditionalTransfersCalldata(
        address borrower,
        address lender,
        address fulfiller,
        ConduitTransfer[] calldata additionalTransfers
    ) internal pure {
        uint256 i = 0;
        for (i; i < additionalTransfers.length;) {
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
        ConduitTransfer[] memory additionalTransfers,
        LoanManager.Loan memory loan
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

    function _transferConduitTransfers(ConduitTransfer[] memory transfers) internal {
        uint256 i = 0;
        uint256 amount = 0;
        for (i; i < transfers.length;) {
            amount = transfers[i].amount;
            if (amount > 0) {
                if (transfers[i].itemType == ConduitItemType.ERC20) {
                    // erc20 transfer

                    SafeTransferLib.safeTransferFrom(transfers[i].token, transfers[i].from, transfers[i].to, amount);
                } else if (transfers[i].itemType == ConduitItemType.ERC721) {
                    // erc721 transfer
                    if (amount > 1) {
                        revert InvalidItemAmount();
                    }
                    ERC721(transfers[i].token).transferFrom(transfers[i].from, transfers[i].to, transfers[i].identifier);
                } else if (transfers[i].itemType == ConduitItemType.ERC1155) {
                    // erc1155 transfer
                    ERC1155(transfers[i].token).safeTransferFrom(
                        transfers[i].from, transfers[i].to, transfers[i].identifier, amount, new bytes(0)
                    );
                } else {
                    revert NativeAssetsNotSupported();
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _transferItem(
        ItemType itemType,
        address token,
        uint256 identifier,
        uint256 amount,
        address from,
        address to
    ) internal {
        if (token.code.length == 0) {
            revert InvalidItemTokenNoCode();
        }
        if (amount > 0) {
            if (itemType == ItemType.ERC20) {
                if (identifier > 0) {
                    revert InvalidItemIdentifier();
                }
                SafeTransferLib.safeTransferFrom(token, from, to, amount);
            } else if (itemType == ItemType.ERC721) {
                // erc721 transfer
                if (amount > 1) {
                    revert InvalidItemAmount();
                }
                ERC721(token).transferFrom(from, to, identifier);
            } else if (itemType == ItemType.ERC1155) {
                // erc1155 transfer
                ERC1155(token).safeTransferFrom(from, to, identifier, amount, new bytes(0));
            } else {
                revert InvalidItemType();
            }
        } else {
            revert InvalidItemAmount();
        }
    }

    function _transferSpentItems(SpentItem[] memory transfers, address from, address to) internal {
        if (transfers.length > 0) {
            uint256 i = 0;
            for (i; i < transfers.length;) {
                _transferItem(
                    transfers[i].itemType, transfers[i].token, transfers[i].identifier, transfers[i].amount, from, to
                );
                unchecked {
                    ++i;
                }
            }
        } else {
            revert InvalidTransferLength();
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

    /**
     * @dev the erc721 name of the contract
     * @return                   The name of the contract as a string
     */
    function name() public pure override returns (string memory) {
        return "Starport Loan Manager";
    }

    /**
     * @dev the erc721 symbol of the contract
     * @return                   The symbol of the contract as a string
     */
    function symbol() public pure override returns (string memory) {
        return "SLM";
    }

    /**
     * @dev  helper to check if a loan is active
     * @param loanId            The id of the loan
     * @return                  True if the loan is active
     */
    function active(uint256 loanId) public view returns (bool) {
        return _getExtraData(loanId) == uint8(FieldFlags.ACTIVE);
    }

    /**
     * @dev  helper to check if a loan is inactive
     * @param loanId            The id of the loan
     * @return                  True if the loan is inactive
     */
    function inactive(uint256 loanId) public view returns (bool) {
        return _getExtraData(loanId) == uint8(FieldFlags.INACTIVE);
    }

    /**
     * @dev  helper to check if a loan is initialized(ie. has never been opened)
     * @param loanId            The id of the loan
     * @return                  True if the loan is initialized
     */
    function initialized(uint256 loanId) public view returns (bool) {
        return _getExtraData(loanId) == uint8(FieldFlags.INITIALIZED);
    }

    /**
     * @dev  erc721 tokenURI override
     * @param loanId            The id of the loan
     * @return                  the string uri of the loan
     */
    function tokenURI(uint256 loanId) public view override returns (string memory) {
        if (!_issued(loanId)) {
            revert InvalidLoan();
        }
        return string("");
    }

    function _issued(uint256 loanId) internal view returns (bool) {
        return (_getExtraData(loanId) > uint8(0));
    }

    /**
     * @dev  helper to check if a loan was issued ever(getExtraData > 0)
     * @param loanId            The id of the loan
     * @return                  True if the loan is initialized
     */
    function issued(uint256 loanId) external view returns (bool) {
        return _issued(loanId);
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
        uint256 tokenId = loan.getId();
        if (!_issued(tokenId)) {
            revert InvalidLoan();
        }
        if (_exists(tokenId)) {
            _burn(tokenId);
        }
        _setExtraData(tokenId, uint8(FieldFlags.INACTIVE));

        if (loan.issuer.code.length > 0) {
            loan.issuer.call(abi.encodeWithSelector(LoanSettledCallback.onLoanSettled.selector, loan));
        }
        emit Close(tokenId);
    }

    /**
     * @dev set's the default fee Data
     * only owner can call
     * @param feeTo_  The feeToAddress
     * @param defaultFeeRake_ the default fee rake in WAD denomination(1e17 = 10%)
     */
    function setFeeData(address feeTo_, uint96 defaultFeeRake_) external onlyOwner {
        feeTo = feeTo_;
        defaultFeeRake = defaultFeeRake_;
    }

    /**
     * @dev set's fee override's for specific tokens
     * only owner can call
     * @param token  The token to override
     * @param overrideValue the new value in WAD denomination to override(1e17 = 10%)
     */
    function setFeeOverride(address token, uint96 overrideValue) external onlyOwner {
        feeOverride[token].enabled = true;
        feeOverride[token].amount = overrideValue;
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
            Fee memory feeOverride = feeOverride[debt[i].token];
            feeItems[i].identifier = 0; //fees are native or erc20
            if (debt[i].itemType == ItemType.NATIVE || debt[i].itemType == ItemType.ERC20) {
                uint256 amount = debt[i].amount.mulDiv(
                    !feeOverride.enabled ? defaultFeeRake : feeOverride.amount,
                    (debt[i].itemType == ItemType.NATIVE) ? 1e18 : 10 ** ERC20(debt[i].token).decimals()
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
    function _issueLoanManager(Loan memory loan) internal {
        loan.start = block.timestamp;
        loan.originator = msg.sender;

        bytes memory encodedLoan = abi.encode(loan);

        uint256 loanId = loan.getId();
        if (_issued(loanId)) {
            revert LoanExists();
        }
        _setExtraData(loanId, uint8(FieldFlags.ACTIVE));
        if (loan.issuer.code.length > 0) {
            _safeMint(loan.issuer, loanId, encodedLoan);
        }
        emit Open(loanId, loan);
    }
}
