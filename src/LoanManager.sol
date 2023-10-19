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

    constructor(ConsiderationInterface seaport_) {
        seaport = seaport_;
        address custodian = address(new Custodian(this, address(seaport)));

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
     * @dev  internal method to call the custody selector of the custodian if it does not share
     * the same codehash as the default custodian
     * @param consideration the receivedItems[]
     * @param orderHashes  the order hashes of the seaport txn
     * @param contractNonce the nonce of the current contract offerer
     * @param context  the abi encoded bytes data of the order
     */
    function _callCustody(
        ReceivedItem[] calldata consideration,
        bytes32[] calldata orderHashes,
        uint256 contractNonce,
        bytes calldata context
    ) internal {
        address custodian = StarPortLib.getCustodian(context);
        // Comparing the retrieved code hash with a known hash
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(custodian)
        }
        if (
            codeHash != DEFAULT_CUSTODIAN_CODE_HASH
                && Custodian(payable(custodian)).custody(consideration, orderHashes, contractNonce, context)
                    != Custodian.custody.selector
        ) {
            revert InvalidCustodian();
        }
    }

    /**
     * @dev previews the order for this contract offerer.
     *
     * @param caller        The address of the contract fulfiller.
     * @param fulfiller        The address of the contract fulfiller.
     * @param minimumReceivedFromBorrower  The minimum the fulfiller must receive.
     * @param maximumSpentFromBorrower     The most a fulfiller will spend
     * @param context          The context of the order.
     * @return offer     The items spent by the order.
     * @return consideration  The items received by the order.
     */
    function previewOrder(
        address caller,
        address fulfiller,
        SpentItem[] calldata minimumReceivedFromBorrower,
        SpentItem[] calldata maximumSpentFromBorrower,
        bytes calldata context // encoded based on the schemaID
    ) public returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        Actions action = StarPortLib.getAction(context);
        if (action == Actions.Origination) {
            (, LoanManager.Obligation memory obligation) = abi.decode(context, (Actions, LoanManager.Obligation));

            bool feeOn;
            if (obligation.debt.length == 0) {
                revert InvalidDebtLength();
            }
            if (maximumSpentFromBorrower.length == 0) {
                revert InvalidMaximumSpentEmpty();
            }
            consideration = maximumSpentFromBorrower.toReceivedItems(obligation.custodian);
            if (feeTo != address(0)) {
                feeOn = true;
            }
            address receiver = obligation.borrower;

            // we settle via seaport channels if caveats are present
            if (fulfiller != receiver || obligation.caveats.length > 0) {
                bytes32 caveatHash = keccak256(
                    encodeWithSaltAndBorrowerCounter(
                        obligation.borrower, obligation.salt, keccak256(abi.encode(obligation.caveats))
                    )
                );
                SpentItem[] memory debt = obligation.debt;
                offer = new SpentItem[](debt.length + 1);
                SpentItem[] memory feeItems = !feeOn ? new SpentItem[](0) : _feeRake(debt);

                for (uint256 i; i < debt.length;) {
                    if (
                        debt[i].itemType == ItemType.ERC721_WITH_CRITERIA
                            || debt[i].itemType == ItemType.ERC1155_WITH_CRITERIA
                    ) {
                        revert InvalidDebtType();
                    }
                    offer[i] = SpentItem({
                        itemType: debt[i].itemType,
                        token: debt[i].token,
                        identifier: debt[i].identifier,
                        amount: debt[i].amount
                    });
                    if (feeOn && feeItems[i].amount > 0) {
                        offer[i].amount = debt[i].amount - feeItems[i].amount;
                    }
                    unchecked {
                        ++i;
                    }
                }

                offer[debt.length] = SpentItem({
                    itemType: ItemType.ERC721,
                    token: address(this),
                    identifier: uint256(caveatHash),
                    amount: 1
                });
            } else if (feeOn) {
                SpentItem[] memory debt = obligation.debt;
                offer = new SpentItem[](debt.length);

                SpentItem[] memory feeItems = !feeOn ? new SpentItem[](0) : _feeRake(debt);

                for (uint256 i; i < debt.length;) {
                    offer[i] = SpentItem({
                        itemType: debt[i].itemType,
                        token: debt[i].token,
                        identifier: debt[i].identifier,
                        amount: debt[i].amount
                    });
                    if (feeItems[i].amount > 0) {
                        offer[i].amount = debt[i].amount - feeItems[i].amount;
                    }
                    unchecked {
                        ++i;
                    }
                }
            }
        } else if (action == Actions.Refinance) {
            (, LoanManager.Loan memory loan, bytes memory newPricingData) =
                abi.decode(context, (Actions, LoanManager.Loan, bytes));

            consideration = _getRefinanceConsiderationsPreview(loan, newPricingData, fulfiller);
            // if for malicious or non-malicious the refinanceConsideration is zero
            if (consideration.length == 0) {
                revert InvalidNoRefinanceConsideration();
            }
        } else {
            revert InvalidAction();
        }
    }

    function _getRefinanceConsiderationsPreview(
        LoanManager.Loan memory loan,
        bytes memory newPricingData,
        address fulfiller
    ) internal view returns (ReceivedItem[] memory consideration) {
        (
            // used to update the new loan amount
            ReceivedItem[] memory considerationPayment,
            ReceivedItem[] memory carryPayment,
            ReceivedItem[] memory additionalPayment
        ) = Pricing(loan.terms.pricing).isValidRefinance(loan, newPricingData, fulfiller);

        consideration = _mergeConsiderations(considerationPayment, carryPayment, additionalPayment);
        consideration = _removeZeroAmounts(consideration);
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
     * @dev fills and verifies the incoming obligation
     *
     * @param fulfiller the new value in WAD denomination to override(1e17 = 10%)
     * @param maximumSpentFromBorrower the maximum incoming items from the order
     * @param context bytes encoded abi of the obligation
     */
    function _fillObligationAndVerify(
        address fulfiller,
        SpentItem[] calldata maximumSpentFromBorrower,
        bytes calldata context
    ) internal returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        bool feesOn = false;
        if (feeTo != address(0)) {
            feesOn = true;
        }
        (, LoanManager.Obligation memory obligation) = abi.decode(context, (Actions, LoanManager.Obligation));

        if (obligation.debt.length == 0) {
            revert InvalidDebtLength();
        }
        if (maximumSpentFromBorrower.length == 0) {
            revert InvalidMaximumSpentEmpty();
        }
        consideration = maximumSpentFromBorrower.toReceivedItems(obligation.custodian);

        address receiver = obligation.borrower;
        bool enforceCaveats = fulfiller != receiver || obligation.caveats.length > 0;
        if (enforceCaveats || feesOn) {
            receiver = address(this);
        }
        Originator.Response memory response = Originator(obligation.originator).execute(
            Originator.Request({
                custodian: obligation.custodian,
                receiver: receiver,
                collateral: maximumSpentFromBorrower,
                debt: obligation.debt,
                details: obligation.details,
                approval: obligation.approval
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
                    obligation.borrower, obligation.salt, keccak256(abi.encode(obligation.caveats))
                )
            );
            usedSalts.validateSalt(obligation.borrower, obligation.salt);
            uint256 i = 0;
            for (; i < obligation.caveats.length;) {
                if (!CaveatEnforcer(obligation.caveats[i].enforcer).enforceCaveat(obligation.caveats[i].terms, loan)) {
                    revert InvalidOrigination();
                }
                unchecked {
                    ++i;
                }
            }
            offer = _setOffer(loan.debt, caveatHash, feesOn);
        } else if (feesOn) {
            offer = _setOffer(loan.debt, bytes32(0), feesOn);
        }
        _issueLoanManager(loan, response.issuer.code.length > 0);
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
    ) external onlySeaport returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        Actions action = StarPortLib.getAction(context);
        if (action == Actions.Origination) {
            (offer, consideration) = _fillObligationAndVerify(fulfiller, maximumSpent, context);
        } else if (action == Actions.Refinance) {
            consideration = _refinance(fulfiller, context);
        } else {
            revert InvalidAction();
        }
    }

    /**
     * @dev moves the fee's collected to the feeTo address
     *
     * @param feeItem The feeItem to payout
     */
    function _moveFeesToReceived(SpentItem memory feeItem) internal {
        if (feeItem.itemType == ItemType.NATIVE) {
            payable(feeTo).call{value: feeItem.amount}("");
        } else if (feeItem.itemType == ItemType.ERC20) {
            ERC20(feeItem.token).transfer(feeTo, feeItem.amount);
        }
    }

    /**
     * @dev enables the debt to be spent via seaport
     *
     * @param debt The item to make available to seaport
     */
    function _enableDebtWithSeaport(SpentItem memory debt) internal {
        //approve consideration based on item type
        if (debt.itemType == ItemType.NATIVE) {
            payable(address(seaport)).call{value: debt.amount}("");
        } else if (debt.itemType == ItemType.ERC721) {
            ERC721(debt.token).approve(address(seaport), debt.identifier);
        } else if (debt.itemType == ItemType.ERC1155) {
            ERC1155(debt.token).setApprovalForAll(address(seaport), true);
        } else if (debt.itemType == ItemType.ERC20) {
            ERC20(debt.token).approve(address(seaport), debt.amount);
        } else {
            revert InvalidDebtType();
        }
    }

    /**
     * @dev set's the offer item to be spent via seaport
     *
     * @param debt The items to make available to seaport
     * @param caveatHash the caveat hash if any
     * @param feeOn if we're collecting fees
     */
    function _setOffer(SpentItem[] memory debt, bytes32 caveatHash, bool feesOn)
        internal
        returns (SpentItem[] memory offer)
    {
        uint256 caveatLength = (caveatHash == bytes32(0)) ? 0 : 1;
        offer = new SpentItem[](debt.length + caveatLength);
        SpentItem[] memory feeItems = !feesOn ? new SpentItem[](0) : _feeRake(debt);
        for (uint256 i; i < debt.length;) {
            offer[i] = SpentItem({
                itemType: debt[i].itemType,
                token: debt[i].token,
                identifier: debt[i].identifier,
                amount: debt[i].amount
            });
            if (feesOn) {
                offer[i].amount = debt[i].amount - feeItems[i].amount;
                _moveFeesToReceived(feeItems[i]);
            }
            _enableDebtWithSeaport(offer[i]);
            unchecked {
                ++i;
            }
        }
        if (caveatHash != bytes32(0)) {
            offer[debt.length] =
                SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: uint256(caveatHash), amount: 1});
        }
    }

    /**
     * @dev override the transferFrom so that onlyseaport can call it
     * shim it so that it does a false success so seaport can tell us
     * to move caveatHash tokens even though none are minted
     * this allows caveatHash tokens to be signed into the seaport order and get guarentee's from seaport on execution
     * @param from the address to send from (if not the LM, then revert CannotTransferLoans()
     * @param to the receiving party
     * @param tokenId the tokenId (only caveatHash tokens are supported and aren't actually issued/sent)
     */
    function transferFrom(address from, address to, uint256 tokenId) public payable override onlySeaport {
        if (address(this) != from) revert CannotTransferLoans();
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
        Actions action = StarPortLib.getAction(context);
        if (action == Actions.Origination) {
            _callCustody(consideration, orderHashes, contractNonce, context);
        }
        ratifyOrderMagicValue = ContractOffererInterface.ratifyOrder.selector;
    }

    /**
     * @dev Helper to determine if an interface is supported by this contract
     *
     * @param interfaceId       The interface to check
     * @return bool return true if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return interfaceId == type(ContractOffererInterface).interfaceId || interfaceId == type(ERC721).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev internal method for conducting a refinance
     *
     * @param fulfiller         The address who is executing the seaport txn
     * @param context           The abi encoded bytes data passed with the order
     * @return bool return true if the interface is supported
     */
    function _refinance(address fulfiller, bytes calldata context)
        internal
        returns (ReceivedItem[] memory consideration)
    {
        (, LoanManager.Loan memory loan, bytes memory newPricingData) =
            abi.decode(context, (Actions, LoanManager.Loan, bytes));

        (
            ReceivedItem[] memory considerationPayment,
            ReceivedItem[] memory carryPayment,
            ReceivedItem[] memory additionalPayment
        ) = Pricing(loan.terms.pricing).isValidRefinance(loan, newPricingData, fulfiller);

        consideration = _mergeConsiderations(considerationPayment, carryPayment, additionalPayment);
        consideration = _removeZeroAmounts(consideration);
        // if for malicious or non-malicious the refinanceConsideration is zero
        if (consideration.length == 0) {
            revert InvalidNoRefinanceConsideration();
        }

        _settle(loan);

        for (uint256 i; i < loan.debt.length;) {
            loan.debt[i].amount = considerationPayment[i].amount;
            unchecked {
                ++i;
            }
        }

        loan.terms.pricingData = newPricingData;
        loan.originator = fulfiller;
        loan.issuer = fulfiller;
        loan.start = block.timestamp;
        _issueLoanManager(loan, fulfiller.code.length > 0);
    }

    /**
     * @dev receive eth method
     * if we are able to increment the counter in seaport that means we have not entered into seaport
     * revert with NotEnteredViaSeaport()
     */
    receive() external payable {
        try seaport.incrementCounter() {
            revert NotEnteredViaSeaport();
        } catch {}
    }

    /**
     * @dev onERC1155Received handler
     * if we are able to increment the counter in seaport that means we have not entered into seaport
     * we dont add for 721 as they are able to ignore the on handler call as apart of the spec
     * revert with NotEnteredViaSeaport()
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        try seaport.incrementCounter() {
            revert NotEnteredViaSeaport();
        } catch {}
        return this.onERC1155Received.selector;
    }
}
