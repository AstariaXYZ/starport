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

import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {Custodian} from "starport-core/Custodian.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {ConduitHelper} from "starport-core/ConduitHelper.sol";

interface LoanSettledCallback {
    function onLoanSettled(LoanManager.Loan calldata loan) external;
}

contract LoanManager is ContractOffererInterface, ConduitHelper, Ownable, ERC721 {
    using FixedPointMathLib for uint256;

    using {StarPortLib.toReceivedItems} for SpentItem[];
    using {StarPortLib.getId} for LoanManager.Loan;
    using {StarPortLib.validateSalt} for mapping(address => mapping(bytes32 => bool));

    ConsiderationInterface public immutable seaport;
    address payable public immutable defaultCustodian;
    bytes32 public immutable DEFAULT_CUSTODIAN_CODE_HASH;
    bytes32 internal immutable _DOMAIN_SEPARATOR;

    // Define the EIP712 domain and typehash constants for generating signatures
    bytes32 constant EIP_DOMAIN = keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant INTENT_ORIGINATION_TYPEHASH =
        keccak256("IntentOrigination(bytes32 hash,bytes32 salt,uint256 nonce)");
    bytes32 constant VERSION = keccak256("0");

    mapping(address => mapping(bytes32 => bool)) public usedSalts;
    mapping(address => uint256) public borrowerNonce; //needs to be invalidated

    address public feeTo;
    uint96 public defaultFeeRake;
    //contract to token //fee rake
    mapping(address => Fee) public exoticFee;

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
        ItemType itemType;
        address token;
        uint88 rake;
    }

    event Close(uint256 loanId);
    event Open(uint256 loanId, LoanManager.Loan loan);
    event SeaportCompatibleContractDeployed();

    error CannotTransferLoans();
    error ConduitTransferError();
    error InvalidConduit();
    error InvalidRefinance();
    error NotSeaport();
    error NotLoanCustodian();
    error InvalidAction();
    error InvalidLoan(uint256);
    error InvalidMaximumSpentEmpty();
    error InvalidDebt();
    error InvalidOrigination();
    error InvalidNoRefinanceConsideration();

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

    // Encode the data with the account's nonce for generating a signature
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

    function name() public pure override returns (string memory) {
        return "Starport Loan Manager";
    }

    function symbol() public pure override returns (string memory) {
        return "SLM";
    }

    // MODIFIERS
    modifier onlySeaport() {
        if (msg.sender != address(seaport)) {
            revert NotSeaport();
        }
        _;
    }

    function active(uint256 loanId) public view returns (bool) {
        return _getExtraData(loanId) == uint8(FieldFlags.ACTIVE);
    }

    function inactive(uint256 loanId) public view returns (bool) {
        return _getExtraData(loanId) == uint8(FieldFlags.INACTIVE);
    }

    function initialized(uint256 loanId) public view returns (bool) {
        return _getExtraData(loanId) == uint8(FieldFlags.INITIALIZED);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) {
            revert InvalidLoan(tokenId);
        }
        return string("");
    }

    function _issued(uint256 tokenId) internal view returns (bool) {
        return (_getExtraData(tokenId) > uint8(0));
    }

    function issued(uint256 tokenId) external view returns (bool) {
        return _issued(tokenId);
    }

    //break the revert of the ownerOf method, so we can ensure anyone calling it in the settlement pipeline wont halt
    function ownerOf(uint256 loanId) public view override returns (address) {
        //not hasn't been issued but exists if we own it
        return _issued(loanId) && !_exists(loanId) ? address(this) : _ownerOf(loanId);
    }

    function settle(Loan memory loan) external {
        if (msg.sender != loan.custodian) {
            revert NotLoanCustodian();
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

        if (loan.issuer.code.length > 0) {
            loan.issuer.call(abi.encodeWithSelector(LoanSettledCallback.onLoanSettled.selector, loan));
        }
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
        // Comparing the retrieved code hash with a known hash
        bytes32 codeHash;
        assembly {
            codeHash := extcodehash(custodian)
        }
        if (codeHash != DEFAULT_CUSTODIAN_CODE_HASH) {
            if (
                Custodian(payable(custodian)).custody(consideration, orderHashes, contractNonce, context)
                    != Custodian.custody.selector
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
    ) public view returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        LoanManager.Obligation memory obligation = abi.decode(context, (LoanManager.Obligation));

        if (obligation.debt.length == 0) {
            revert InvalidDebt();
        }
        if (maximumSpentFromBorrower.length == 0) {
            revert InvalidMaximumSpentEmpty();
        }
        consideration = maximumSpentFromBorrower.toReceivedItems(obligation.custodian);
        if (feeTo != address(0)) {
            consideration = _mergeFees(consideration, _feeRake(obligation.debt));
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

            for (uint256 i; i < debt.length;) {
                offer[i] = debt[i];
                unchecked {
                    ++i;
                }
            }

            offer[debt.length] =
                SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: uint256(caveatHash), amount: 1});
        }
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

    function setFeeData(address feeTo_, uint96 defaultFeeRake_) external onlyOwner {
        feeTo = feeTo_;
        defaultFeeRake = defaultFeeRake_;
    }

    function setExoticFee(address exotic, Fee memory fee) external onlyOwner {
        exoticFee[exotic] = fee;
    }

    function getExoticFee(SpentItem memory exotic) public view returns (Fee memory fee) {
        return exoticFee[exotic.token];
    }

    function _feeRake(SpentItem[] memory debt) internal view returns (ReceivedItem[] memory feeConsideration) {
        uint256 i = 0;
        feeConsideration = new ReceivedItem[](debt.length);
        for (; i < debt.length;) {
            feeConsideration[i].identifier = 0; //fees are native or erc20
            feeConsideration[i].recipient = payable(feeTo);
            if (debt[i].itemType == ItemType.NATIVE || debt[i].itemType == ItemType.ERC20) {
                feeConsideration[i].amount = debt[i].amount.mulDiv(
                    defaultFeeRake, debt[i].itemType == ItemType.NATIVE ? 1e18 : 10 ** ERC20(debt[i].token).decimals()
                );
                feeConsideration[i].token = debt[i].token;
                feeConsideration[i].itemType = debt[i].itemType;
            } else {
                Fee memory fee = getExoticFee(debt[i]);
                feeConsideration[i].itemType = fee.itemType;
                feeConsideration[i].token = fee.token;
                feeConsideration[i].amount = fee.rake; //flat fee
            }
            unchecked {
                ++i;
            }
        }
    }

    function _mergeFees(ReceivedItem[] memory first, ReceivedItem[] memory second)
        internal
        pure
        returns (ReceivedItem[] memory consideration)
    {
        consideration = new ReceivedItem[](first.length + second.length);
        uint256 i = 0;
        for (; i < first.length;) {
            consideration[i] = first[i];
            unchecked {
                ++i;
            }
        }
        for (i = first.length; i < second.length;) {
            consideration[i] = second[i];
            unchecked {
                ++i;
            }
        }
    }

    function _fillObligationAndVerify(
        address fulfiller,
        SpentItem[] calldata maximumSpentFromBorrower,
        bytes calldata context
    ) internal returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        LoanManager.Obligation memory obligation = abi.decode(context, (LoanManager.Obligation));

        if (obligation.debt.length == 0) {
            revert InvalidDebt();
        }
        if (maximumSpentFromBorrower.length == 0) {
            revert InvalidMaximumSpentEmpty();
        }
        consideration = maximumSpentFromBorrower.toReceivedItems(obligation.custodian);
        if (feeTo != address(0)) {
            consideration = _mergeFees(consideration, _feeRake(obligation.debt));
        }
        address receiver = obligation.borrower;
        bool enforceCaveats = fulfiller != receiver || obligation.caveats.length > 0;
        if (enforceCaveats) {
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
    ) external onlySeaport returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        (offer, consideration) = _fillObligationAndVerify(fulfiller, maximumSpent, context);
    }

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
            revert InvalidDebt();
        }
    }

    function _setOffer(SpentItem[] memory debt, bytes32 caveatHash) internal returns (SpentItem[] memory offer) {
        offer = new SpentItem[](debt.length + 1);

        for (uint256 i; i < debt.length;) {
            offer[i] = debt[i];
            _enableDebtWithSeaport(debt[i]);
            unchecked {
                ++i;
            }
        }

        offer[debt.length] =
            SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: uint256(caveatHash), amount: 1});
    }

    function transferFrom(address from, address to, uint256 tokenId) public payable override {
        //active loans do nothing
        if (from != address(this)) revert CannotTransferLoans();
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public payable override {
        if (from != address(this)) revert CannotTransferLoans();
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

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ContractOffererInterface)
        returns (bool)
    {
        return interfaceId == type(ContractOffererInterface).interfaceId || interfaceId == type(ERC721).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function refinance(LoanManager.Loan memory loan, bytes memory newPricingData, address conduit) external {
        (,, address conduitController) = seaport.information();

        if (ConduitControllerInterface(conduitController).ownerOf(conduit) != msg.sender) {
            revert InvalidConduit();
        }
        (
            // used to update to repay the lender
            ReceivedItem[] memory considerationPayment,
            // used to pay the carry amount
            ReceivedItem[] memory carryPayment,
            // considerationPayment + carryPayment = amount = new debt

            // used for any additional payments beyond consideration and carry
            ReceivedItem[] memory additionalPayment
        ) = Pricing(loan.terms.pricing).isValidRefinance(loan, newPricingData, msg.sender);

        _settle(loan);

        if (carryPayment.length > 0) {
            for (uint256 i; i < loan.debt.length;) {
                loan.debt[i].amount = considerationPayment[i].amount + carryPayment[i].amount;
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i; i < loan.debt.length;) {
                loan.debt[i].amount = considerationPayment[i].amount;
                unchecked {
                    ++i;
                }
            }
        }

        ReceivedItem[] memory refinanceConsideration =
            _mergeAndRemoveZeroAmounts(considerationPayment, carryPayment, additionalPayment);

        // if for malicious or non-malicious the refinanceConsideration is zero
        if (refinanceConsideration.length == 0) {
            revert InvalidNoRefinanceConsideration();
        }

        if (
            ConduitInterface(conduit).execute(_packageTransfers(refinanceConsideration, msg.sender))
                != ConduitInterface.execute.selector
        ) {
            revert ConduitTransferError();
        }

        loan.terms.pricingData = newPricingData;
        loan.originator = msg.sender;
        loan.issuer = msg.sender;
        loan.start = block.timestamp;
        _issueLoanManager(loan, msg.sender.code.length > 0);
    }

    receive() external payable {}
}
