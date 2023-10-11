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

import {ItemType, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {TokenReceiverInterface} from "starport-core/interfaces/TokenReceiverInterface.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";
import {SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
import {ConduitHelper} from "starport-core/ConduitHelper.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";

contract Custodian is ContractOffererInterface, TokenReceiverInterface, ConduitHelper, ERC721 {
    using {StarPortLib.getId} for LoanManager.Loan;

    LoanManager public immutable LM;
    address public immutable seaport;

    mapping(address => mapping(address => bool)) public repayApproval;

    event RepayApproval(address borrower, address repayer, bool approved);
    event SeaportCompatibleContractDeployed();

    error NotSeaport();
    error InvalidRepayer();
    error InvalidFulfiller();
    error InvalidHandlerExecution();
    error InvalidLoan();

    constructor(LoanManager LM_, address seaport_) {
        seaport = seaport_;
        LM = LM_;
        emit SeaportCompatibleContractDeployed();
    }

    function getBorrower(LoanManager.Loan memory loan) public view returns (address) {
        uint256 loanId = uint256(keccak256(abi.encode(loan)));
        return _exists(loanId) ? ownerOf(loanId) : loan.borrower;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (!_exists(tokenId)) {
            revert InvalidLoan();
        }
        return string("");
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ContractOffererInterface)
        returns (bool)
    {
        return interfaceId == type(ERC721).interfaceId || interfaceId == type(ContractOffererInterface).interfaceId
            || super.supportsInterface(interfaceId);
    }

    function name() public pure override returns (string memory) {
        return "Starport Custodian";
    }

    function symbol() public pure override returns (string memory) {
        return "SC";
    }

    //MODIFIERS

    modifier onlySeaport() {
        if (msg.sender != address(seaport)) {
            revert NotSeaport();
        }
        _;
    }

    //EXTERNAL FUNCTIONS

    function mint(LoanManager.Loan calldata loan) external {
        bytes memory encodedLoan = abi.encode(loan);
        uint256 loanId = uint256(keccak256(encodedLoan));
        if (loan.custodian != address(this) || !LM.issued(loanId)) {
            revert InvalidLoan();
        }

        _safeMint(loan.borrower, loanId, encodedLoan);
    }

    function setRepayApproval(address who, bool approved) external {
        repayApproval[msg.sender][who] = approved;
        emit RepayApproval(msg.sender, who, approved);
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

    function custody(
        ReceivedItem[] calldata consideration,
        bytes32[] calldata orderHashes,
        uint256 contractNonce,
        bytes calldata context
    ) external virtual returns (bytes4 selector) {
        selector = Custodian.custody.selector;
    }

    //todo work with seaport
    function getSeaportMetadata() external pure returns (string memory, Schema[] memory schemas) {
        //adhere to sip data, how to encode the context and what it is
        //TODO: add in the context for the loan
        //you need to parse LM Open events for the loan and abi encode it
        schemas = new Schema[](1);
        schemas[0] = Schema(8, "");
        return ("Loans", schemas);
    }

    // PUBLIC FUNCTIONS

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
    ) public view returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
        offer = loan.collateral;

        if (!LM.issued(loan.getId())) {
            revert InvalidLoan();
        }
        if (SettlementHook(loan.terms.hook).isActive(loan)) {
            address borrower = getBorrower(loan);
            if (fulfiller != borrower && !repayApproval[borrower][fulfiller]) {
                revert InvalidRepayer();
            }

            (ReceivedItem[] memory paymentConsiderations, ReceivedItem[] memory carryFeeConsideration) =
                Pricing(loan.terms.pricing).getPaymentConsideration(loan);

            consideration = _mergeConsiderations(paymentConsiderations, carryFeeConsideration, new ReceivedItem[](0));
            consideration = _removeZeroAmounts(consideration);
        } else {
            address authorized;
            (consideration, authorized) = SettlementHandler(loan.terms.handler).getSettlement(loan);

            if (authorized != address(0) && fulfiller != authorized) {
                revert InvalidFulfiller();
            }
        }
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        public
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        public
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC1155BatchReceived.selector;
    }

    //INTERNAL FUNCTIONS

    function _fillObligationAndVerify(address fulfiller, SpentItem[] calldata maximumSpent, bytes calldata context)
        internal
        returns (SpentItem[] memory offer, ReceivedItem[] memory consideration)
    {
        LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
        if (!LM.issued(loan.getId())) {
            revert InvalidLoan();
        }
        if (SettlementHook(loan.terms.hook).isActive(loan)) {
            address borrower = getBorrower(loan);
            if (fulfiller != borrower && !repayApproval[borrower][fulfiller]) {
                revert InvalidRepayer();
            }

            offer = loan.collateral;
            _beforeApprovalsSetHook(fulfiller, maximumSpent, context);
            _setOfferApprovalsWithSeaport(offer);

            (ReceivedItem[] memory paymentConsiderations, ReceivedItem[] memory carryFeeConsideration) =
                Pricing(loan.terms.pricing).getPaymentConsideration(loan);

            consideration = _mergeConsiderations(paymentConsiderations, carryFeeConsideration, new ReceivedItem[](0));
            consideration = _removeZeroAmounts(consideration);

            _settleLoan(loan);
        } else {
            address authorized;
            //add in originator fee
            _beforeSettlementHandlerHook(loan);
            (consideration, authorized) = SettlementHandler(loan.terms.handler).getSettlement(loan);
            _afterSettlementHandlerHook(loan);

            if (authorized != address(0) && authorized == loan.terms.handler) {
                _moveDebtToHandler(loan.collateral, authorized);
                if (SettlementHandler(loan.terms.handler).execute(loan) != SettlementHandler.execute.selector) {
                    revert InvalidHandlerExecution();
                }
                _settleLoan(loan);
            } else if (authorized != address(0) && fulfiller != authorized) {
                revert InvalidFulfiller();
            } else {
                offer = loan.collateral;
                _beforeApprovalsSetHook(fulfiller, maximumSpent, context);
                _setOfferApprovalsWithSeaport(offer);
                _settleLoan(loan);
            }
        }
    }

    //custodian cant get any other assets deposited aside from what the LM supports
    function _enableAssetWithSeaport(SpentItem memory offer) internal {
        //approve consideration based on item type
        if (offer.itemType == ItemType.NATIVE) {
            payable(address(seaport)).call{value: offer.amount}("");
        } else if (offer.itemType == ItemType.ERC721) {
            ERC721(offer.token).approve(address(seaport), offer.identifier);
        } else if (offer.itemType == ItemType.ERC1155) {
            ERC1155(offer.token).setApprovalForAll(address(seaport), true);
        } else if (offer.itemType == ItemType.ERC20) {
            ERC20(offer.token).approve(address(seaport), offer.amount);
        }
    }

    function _setOfferApprovalsWithSeaport(SpentItem[] memory offer) internal {
        for (uint256 i = 0; i < offer.length; i++) {
            _enableAssetWithSeaport(offer[i]);
        }
    }
    //custodian cant get any other assets deposited aside from what the LM supports

    function _transferCollateralToHandler(SpentItem memory offer, address handler) internal {
        //approve consideration based on item type
        if (offer.itemType == ItemType.NATIVE) {
            payable(address(handler)).call{value: offer.amount}("");
        } else if (offer.itemType == ItemType.ERC721) {
            ERC721(offer.token).transferFrom(address(this), handler, offer.identifier);
        } else if (offer.itemType == ItemType.ERC1155) {
            ERC1155(offer.token).safeTransferFrom(address(this), handler, offer.identifier, offer.amount, "");
        } else if (offer.itemType == ItemType.ERC20) {
            ERC20(offer.token).transfer(handler, offer.amount);
        }
    }

    function _moveDebtToHandler(SpentItem[] memory offer, address handler) internal {
        for (uint256 i = 0; i < offer.length; i++) {
            _transferCollateralToHandler(offer[i], handler);
        }
    }

    function _settleLoan(LoanManager.Loan memory loan) internal virtual {
        _beforeSettleLoanHook(loan);
        LM.settle(loan);
        _afterSettleLoanHook(loan);
    }

    function _beforeApprovalsSetHook(address fulfiller, SpentItem[] calldata maximumSpent, bytes calldata context)
        internal
        virtual
    {}

    function _beforeSettlementHandlerHook(LoanManager.Loan memory loan) internal virtual {}

    function _afterSettlementHandlerHook(LoanManager.Loan memory loan) internal virtual {}

    function _beforeSettleLoanHook(LoanManager.Loan memory loan) internal {
        uint256 loanId = loan.getId();
        if (_exists(loanId)) {
            _burn(uint256(keccak256(abi.encode(loan))));
        }
    }

    function _afterSettleLoanHook(LoanManager.Loan memory loan) internal virtual {}

    receive() external payable onlySeaport {}
}
