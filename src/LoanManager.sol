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
pragma solidity =0.8.17;

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";
import {ItemType, OfferItem, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
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
import {ConduitHelper} from "starport-core/ConduitHelper.sol";
import {Enforcer} from "starport-core/Enforcer.sol";
import "forge-std/console.sol";

interface LoanSettledCallback {
    function onLoanSettled(LoanManager.Loan calldata loan) external;
}

contract LoanManager is ConduitHelper, Ownable, ERC721 {
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
    bytes32 public constant INTENT_ORIGINATION_TYPEHASH =
        keccak256("IntentOrigination(bytes32 hash,bytes32 salt,uint256 nonce)");
    bytes32 public constant VERSION = keccak256("0");
    address public feeTo;
    uint96 public defaultFeeRake;
    mapping(address => mapping(bytes32 => bool)) public usedSalts;
    mapping(address => uint256) public borrowerNonce; //needs to be invalidated

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
    event SeaportCompatibleContractDeployed();

    error CannotTransferLoans();
    error ConduitTransferError();
    error InvalidAction();
    error InvalidConduit();
    error InvalidRefinance();
    error InvalidCustodian();
    error InvalidLoan();
    error InvalidMaximumSpentEmpty();
    error InvalidDebtLength();
    error InvalidDebtType();
    error InvalidOrigination();
    error InvalidNoRefinanceConsideration();
    error LoanExists();
    error NotLoanCustodian();
    error NotPayingFees();
    error NotSeaport();
    error NotEnteredViaSeaport();

    error NativeAssetsNotSupported();
    error HashAlreadyInvalidated();
    error InvalidItemType();
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
        emit SeaportCompatibleContractDeployed();
    }


    mapping(address => mapping(bytes32 => bool)) invalidHashes;
    mapping(address => mapping(address => bool)) approvals;

    function originate(
        ConduitTransfer[] calldata additionalTransfers,
        Enforcer.Caveat calldata borrowerCaveat,
        Enforcer.Caveat calldata lenderCaveat,
        LoanManager.Loan memory loan) external payable returns (LoanManager.Loan memory){

        if(msg.sender != loan.borrower){
            _validateAndEnforceCaveats(borrowerCaveat, loan.borrower, additionalTransfers, loan);
        }

        if(msg.sender != loan.issuer && !approvals[loan.issuer][msg.sender]){
        _validateAndEnforceCaveats(lenderCaveat, loan.issuer, additionalTransfers, loan);
        }

        _transferSpentItems(loan.debt, loan.issuer, loan.borrower);
        _transferSpentItems(loan.collateral, loan.borrower, loan.custodian);

        
        if(additionalTransfers.length > 0){
        _validateAdditionalTransfers(loan.borrower, loan.issuer, msg.sender, additionalTransfers);
        _transferConduitTransfers(additionalTransfers);
        }

        loan.start = block.timestamp;
        //mint LM
        _issueLoanManager(loan, true);
        return loan;
    }

    function refinance(
        address lender,
        Enforcer.Caveat calldata lenderCaveat,
        LoanManager.Loan memory loan,
        bytes memory pricingData
        ) external
    {
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

        if(msg.sender != loan.issuer && !approvals[loan.issuer][msg.sender]){
        _validateAndEnforceCaveats(lenderCaveat, loan.issuer, additionalTransfers, loan);
        }

        if(additionalTransfers.length > 0){
        _validateAdditionalTransfers(loan.borrower, loan.issuer, msg.sender, additionalTransfers);
        _transferConduitTransfers(additionalTransfers);
        }

        loan.originator = msg.sender;
        loan.start = block.timestamp;

        _issueLoanManager(loan, msg.sender.code.length > 0);
    }

    function applyRefinanceConsiderationToLoan(LoanManager.Loan memory loan, SpentItem[] memory considerationPayment, SpentItem[] memory carryPayment, bytes memory pricingData) public pure returns(LoanManager.Loan memory) {
        if(considerationPayment.length == 0 || (carryPayment.length != 0 && considerationPayment.length != carryPayment.length) || considerationPayment.length != loan.debt.length) {
        revert MalformedRefinance();
        }

        uint256 i=0;
        if(carryPayment.length > 0){
            for(;i<considerationPayment.length;){
                loan.debt[i].amount = considerationPayment[i].amount + carryPayment[i].amount;

                unchecked {
                ++i;
                }
            }
        }
        else {
            for(;i<considerationPayment.length;){
                loan.debt[i].amount = considerationPayment[i].amount;
                unchecked {
                ++i;
                }
            }
        }
        loan.terms.pricingData = pricingData;
        return loan;
    }

    function _validateAdditionalTransfers(address borrower, address lender, address fulfiller, ConduitTransfer[] memory additionalTransfers) internal pure {
        uint256 i = 0;
        for(i; i<additionalTransfers.length;){
        if(additionalTransfers[i].from != borrower && additionalTransfers[i].from != lender && additionalTransfers[i].from != fulfiller) revert UnauthorizedAdditionalTransferIncluded();
        unchecked {
            ++i;
        }
        }
    }
    function _validateAndEnforceCaveats(Enforcer.Caveat memory caveat, address validator, ConduitTransfer[] memory additionalTransfers, LoanManager.Loan memory loan) internal {
        bytes32 salt = caveat.salt;
        if(salt != bytes32(0)){
        if(invalidHashes[validator][salt]){
            revert HashAlreadyInvalidated();
        }
        else{
            if(salt != bytes32(0)) invalidHashes[validator][salt] = true;
        }
        }

        bytes32 hash = keccak256(abi.encode(caveat.enforcer, caveat.caveat, salt));
        address signer = ecrecover(hash, caveat.approval.v, caveat.approval.r, caveat.approval.s);
        if(signer != validator) revert InvalidCaveatSigner();

        // will revert if invalid
        Enforcer(caveat.enforcer).validate(additionalTransfers, loan, caveat.caveat);
    }

    function _transferConduitTransfers(ConduitTransfer[] memory transfers) internal {
        uint256 i=0;
        for(i; i<transfers.length;){
            if(transfers[i].amount != 0){
            if(transfers[i].itemType == ConduitItemType.ERC20){
                // erc20 transfer
                ERC20(transfers[i].token).transferFrom(transfers[i].from, transfers[i].to, transfers[i].amount);
            }
            else if(transfers[i].itemType == ConduitItemType.ERC721){
                // erc721 transfer
                ERC721(transfers[i].token).transferFrom(transfers[i].from, transfers[i].to, transfers[i].identifier);
            }
            else if(transfers[i].itemType == ConduitItemType.ERC1155){
                // erc1155 transfer
                ERC1155(transfers[i].token).safeTransferFrom(transfers[i].from, transfers[i].to, transfers[i].identifier, transfers[i].amount, new bytes(0));
            }
            else revert NativeAssetsNotSupported();

            }
            unchecked {
            ++i;
            }
        }
    }

    function _transferSpentItems(SpentItem[] memory transfers, address from, address to) internal {
        uint256 i=0;
        for(i; i<transfers.length;){
        if(transfers[i].amount != 0){
            if(transfers[i].itemType == ItemType.ERC20){
            // erc20 transfer
            ERC20(transfers[i].token).transferFrom(from, to, transfers[i].amount);
            }
            else if(transfers[i].itemType == ItemType.ERC721){
            // erc721 transfer
            ERC721(transfers[i].token).transferFrom(from, to, transfers[i].identifier);
            }
            else if(transfers[i].itemType == ItemType.ERC1155){
            // erc1155 transfer
            ERC1155(transfers[i].token).safeTransferFrom(from, to, transfers[i].identifier, transfers[i].amount, new bytes(0));
            }
            else revert NativeAssetsNotSupported();
        }
        unchecked {
            ++i;
        }
        }
    }

    /**
     * @dev previews the order for this contract offerer.
     *
     * @param borrower        The address of the borrower
     * @param salt            The salt of the borrower's obligation
     * @param caveatHash      The hash of the abi.encoded obligation caveats
     * @return                The abi encode packed bytes that include the intent typehash with the salt and nonce and caveatHash
     */
    function encodeWithSaltAndBorrowerCounter(address borrower, bytes32 salt, bytes32 caveatHash)
        public
        view
        virtual
        returns (bytes memory)
    {
        return abi.encodePacked(
            bytes1(0x19),
            bytes1(0x01),
            _DOMAIN_SEPARATOR,
            keccak256(abi.encode(INTENT_ORIGINATION_TYPEHASH, salt, borrowerNonce[borrower], caveatHash))
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
     * @dev  modifier to check if the caller is seaport
     */
    modifier onlySeaport() {
        if (msg.sender != address(seaport)) {
            revert NotSeaport();
        }
        _;
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
     * @dev Gets the metadata for this contract offerer.
     *
     * @return name    The name of the contract offerer.
     * @return schemas The schemas supported by the contract offerer.
     */
    function getSeaportMetadata() external pure returns (string memory, Schema[] memory schemas) {
        schemas = new Schema[](1);
        schemas[0] = Schema(8, "");
        return ("Loans", schemas);
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
    function _feeRake(SpentItem[] memory debt) internal view returns (SpentItem[] memory feeItems) {
        feeItems = new SpentItem[](debt.length);
        uint256 totalDebtItems;
        for (uint256 i = 0; i < debt.length;) {
            Fee memory feeOverride = feeOverride[debt[i].token];
            feeItems[i].identifier = 0; //fees are native or erc20
            if (debt[i].itemType == ItemType.NATIVE || debt[i].itemType == ItemType.ERC20) {
                feeItems[i].amount = debt[i].amount.mulDiv(
                    !feeOverride.enabled ? defaultFeeRake : feeOverride.amount,
                    (debt[i].itemType == ItemType.NATIVE) ? 1e18 : 10 ** ERC20(debt[i].token).decimals()
                );
                feeItems[i].token = debt[i].token;
                feeItems[i].itemType = debt[i].itemType;
                ++totalDebtItems;
            }
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(feeItems, totalDebtItems)
        }
    }

    /**
     * @dev issues a LM token if needed
     * only owner can call
     * @param loan  the loan to issue
     * @param mint if true, mint the token
     */
    function _issueLoanManager(Loan memory loan, bool mint) internal {
        bytes memory encodedLoan = abi.encode(loan);

        uint256 loanId = loan.getId();
        if (_issued(loanId)) {
            revert LoanExists();
        }
        _setExtraData(loanId, uint8(FieldFlags.ACTIVE));
        if (mint) {
            _safeMint(loan.issuer, loanId, encodedLoan);
        }
        emit Open(loanId, loan);
    }

    function issueLoanManager(Loan memory loan, bool mint) external {
        bytes memory encodedLoan = abi.encode(loan);

        uint256 loanId = loan.getId();
        if (_issued(loanId)) {
            revert LoanExists();
        }
        _setExtraData(loanId, uint8(FieldFlags.ACTIVE));
        if (mint) {
            _safeMint(loan.issuer, loanId, encodedLoan);
        }
        emit Open(loanId, loan);
    }
}
