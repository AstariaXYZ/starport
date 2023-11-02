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

import {ItemType, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";
import {SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
import {StarPortLib, Actions} from "starport-core/lib/StarPortLib.sol";
import "forge-std/console2.sol";

contract Custodian is ERC721, ContractOffererInterface {
    using {StarPortLib.getId} for LoanManager.Loan;

    LoanManager public immutable LM;
    ConsiderationInterface public immutable seaport;

    mapping(address => mapping(address => bool)) public repayApproval;

    event RepayApproval(address borrower, address repayer, bool approved);
    event SeaportCompatibleContractDeployed();

    error ImplementInChild();
    error InvalidAction();
    error InvalidFulfiller();
    error InvalidHandlerExecution();
    error InvalidLoan();
    error InvalidRepayer();
    error NotSeaport();
    error NotEnteredViaSeaport();
    error NotLoanManager();

    constructor(LoanManager LM_, ConsiderationInterface seaport_) {
        seaport = seaport_;
        LM = LM_;
        emit SeaportCompatibleContractDeployed();
    }

    /**
     * @dev Fetches the borrower of the loan, first checks to see if we've minted the token for the loan
     * @param loan            Loan to get the borrower of
     * @return address        The address of the loan borrower(returns the ownerOf the token if any) defaults to loan.borrower
     */
    function getBorrower(LoanManager.Loan memory loan) public view returns (address) {
        uint256 loanId = loan.getId();
        return _exists(loanId) ? ownerOf(loanId) : loan.borrower;
    }

    /**
     * @dev  erc721 tokenURI override
     * @param loanId            The id of the custody token/loan
     * @return                  the string uri of the custody token/loan
     */
    function tokenURI(uint256 loanId) public view override returns (string memory) {
        if (!_exists(loanId)) {
            revert InvalidLoan();
        }
        return string("");
    }

    /**
     * @dev Helper to determine if an interface is supported by this contract
     *
     * @param interfaceId       The interface to check
     * @return bool return true if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ContractOffererInterface)
        returns (bool)
    {
        return interfaceId == type(ERC721).interfaceId || interfaceId == type(ContractOffererInterface).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev The name of the ERC721 contract
     *
     * @return string           The name of the contract
     */
    function name() public pure override returns (string memory) {
        return "Starport Custodian";
    }

    /**
     * @dev The symbol of the ERC721 contract
     *
     * @return string           The symbol of the contract
     */
    function symbol() public pure override returns (string memory) {
        return "SC";
    }

    //MODIFIERS
    /**
     * @dev only allows LoanManager to execute the function
     */
    modifier onlyLoanManager() {
        if (msg.sender != address(LM)) {
            revert NotLoanManager();
        }
        _;
    }

    /**
     * @dev only allows seaport to execute the function
     */
    modifier onlySeaport() {
        if (msg.sender != address(seaport)) {
            revert NotSeaport();
        }
        _;
    }

    //EXTERNAL FUNCTIONS
    /**
     * @dev Mints a custody token for a loan.
     *
     * @param loan             The loan to mint a custody token for
     */
    function mint(LoanManager.Loan calldata loan) external {
        bytes memory encodedLoan = abi.encode(loan);
        uint256 loanId = uint256(keccak256(encodedLoan));
        if (loan.custodian != address(this) || !LM.active(loanId)) {
            revert InvalidLoan();
        }

        _safeMint(loan.borrower, loanId, encodedLoan);
    }

    /**
     * @dev Set's approvals for who can repay a loan on behalf of the borrower.
     *
     * @param who              The address of the account to modify approval for
     * @param approved         The approval status
     */
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
        SpentItem[] calldata,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    ) external onlySeaport returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        (Actions action, LoanManager.Loan memory loan) = abi.decode(context, (Actions, LoanManager.Loan));

        if (action == Actions.Repayment && SettlementHook(loan.terms.hook).isActive(loan)) {
            address borrower = getBorrower(loan);
            if (fulfiller != borrower && !repayApproval[borrower][fulfiller]) {
                revert InvalidRepayer();
            }

            offer = loan.collateral;
            _beforeApprovalsSetHook(fulfiller, maximumSpent, context);
            _setOfferApprovalsWithSeaport(offer);

            (SpentItem[] memory payment, SpentItem[] memory carry) =
                Pricing(loan.terms.pricing).getPaymentConsideration(loan);

            consideration = StarPortLib.mergeSpentItemsToReceivedItems(payment, loan.issuer, carry, loan.originator);

            _settleLoan(loan);
        } else if (action == Actions.Settlement && !SettlementHook(loan.terms.hook).isActive(loan)) {
            address authorized;
            //add in originator fee

            _beforeGetSettlement(loan);
            (consideration, authorized) = SettlementHandler(loan.terms.handler).getSettlement(loan);
            _afterGetSettlement(loan);
            if (authorized == address(0) || fulfiller == authorized) {
                offer = loan.collateral;
                _beforeApprovalsSetHook(fulfiller, maximumSpent, context);
                _setOfferApprovalsWithSeaport(offer);
            } else if (authorized == loan.terms.handler || authorized == loan.issuer) {
                _moveCollateralToAuthorized(loan.collateral, authorized);
                _beforeSettlementHandlerHook(loan);
                if (
                    authorized == loan.terms.handler
                        && SettlementHandler(loan.terms.handler).execute(loan, fulfiller)
                            != SettlementHandler.execute.selector
                ) {
                    revert InvalidHandlerExecution();
                }
                _afterSettlementHandlerHook(loan);
            } else {
                revert InvalidFulfiller();
            }
            _settleLoan(loan);
        } else {
            revert InvalidAction();
        }
    }

    /**
     * @dev If any additional state updates are needed when taking custody of a loan
     *
     * @param loan             The loan that was just placed into custody
     * @return selector        The function selector of the custody method
     */
    function custody(LoanManager.Loan memory loan) external virtual onlyLoanManager returns (bytes4 selector) {
        revert ImplementInChild();
    }

    /**
     * @dev returns metadata on how to interact with the offerer contract
     *
     * @return string  the name of the contract
     * @return schemas  an array of supported schemas
     */
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
        (Actions action, LoanManager.Loan memory loan) = abi.decode(context, (Actions, LoanManager.Loan));

        if (!LM.active(loan.getId())) {
            revert InvalidLoan();
        }
        bool loanActive = SettlementHook(loan.terms.hook).isActive(loan);
        if (action == Actions.Repayment && loanActive) {
            address borrower = getBorrower(loan);
            if (fulfiller != borrower && !repayApproval[borrower][fulfiller]) {
                revert InvalidRepayer();
            }
            offer = loan.collateral;

            (SpentItem[] memory payment, SpentItem[] memory carry) =
                Pricing(loan.terms.pricing).getPaymentConsideration(loan);
            consideration = StarPortLib.mergeSpentItemsToReceivedItems(payment, loan.issuer, carry, loan.originator);
        } else if (action == Actions.Settlement && !loanActive) {
            address authorized;
            (consideration, authorized) = SettlementHandler(loan.terms.handler).getSettlement(loan);

            if (authorized == address(0) || fulfiller == authorized) {
                offer = loan.collateral;
            } else if (authorized == loan.terms.handler || authorized == loan.issuer) {} else {
                revert InvalidFulfiller();
            }
        } else {
            revert InvalidAction();
        }
    }

    /**
     * @dev onERC1155Received handler
     * if we are able to increment the counter in seaport that means we have not entered into seaport
     * we dont add for 721 as they are able to ignore the on handler call as apart of the spec
     * revert with NotEnteredViaSeaport()
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) public virtual returns (bytes4) {
        // commenting out because, we are not entering this flow via Seaport after teh new origiantion changes
        // try seaport.incrementCounter() {
        //     revert NotEnteredViaSeaport();
        // } catch {}
        return this.onERC1155Received.selector;
    }

    //INTERNAL FUNCTIONS

    /**
     * @dev enables the collateral deposited to be spent via seaport
     *
     * @param offer The item to make available to seaport
     */
    function _enableAssetWithSeaport(SpentItem memory offer) internal {
        //approve consideration based on item type
        if (offer.itemType == ItemType.ERC721) {
            ERC721(offer.token).approve(address(seaport), offer.identifier);
        } else if (offer.itemType == ItemType.ERC1155) {
            ERC1155(offer.token).setApprovalForAll(address(seaport), true);
        } else if (offer.itemType == ItemType.ERC20) {
            ERC20(offer.token).approve(address(seaport), offer.amount);
        }
    }

    /**
     * @dev set's approvals for the collateral deposited to be spent via seaport
     *
     * @param offer The item to make available to seaport
     */
    function _setOfferApprovalsWithSeaport(SpentItem[] memory offer) internal {
        for (uint256 i = 0; i < offer.length; i++) {
            _enableAssetWithSeaport(offer[i]);
        }
    }
    /**
     * @dev transfers out the collateral to the handler address
     *
     * @param offer             The item to send out of the Custodian
     * @param handler           The address handling the asset further
     */

    function _transferCollateralToHandler(SpentItem memory offer, address handler) internal {
        //approve consideration based on item type
        if (offer.itemType == ItemType.ERC721) {
            ERC721(offer.token).transferFrom(address(this), handler, offer.identifier);
        } else if (offer.itemType == ItemType.ERC1155) {
            ERC1155(offer.token).safeTransferFrom(address(this), handler, offer.identifier, offer.amount, "");
        } else if (offer.itemType == ItemType.ERC20) {
            ERC20(offer.token).transfer(handler, offer.amount);
        }
    }

    /**
     * @dev transfers out the collateral of SpentItem to the handler address
     *
     * @param offer             The SpentItem array to send out of the Custodian
     * @param handler           The address handling the asset further
     */
    function _moveCollateralToAuthorized(SpentItem[] memory offer, address handler) internal {
        for (uint256 i = 0; i < offer.length; i++) {
            _transferCollateralToHandler(offer[i], handler);
        }
    }

    /**
     * @dev settle the loan with the LoanManager
     *
     * @param loan              The the loan to settle
     */
    function _settleLoan(LoanManager.Loan memory loan) internal virtual {
        _beforeSettleLoanHook(loan);
        uint256 loanId = loan.getId();
        if (_exists(loanId)) {
            _burn(loanId);
        }
        LM.settle(loan);
        _afterSettleLoanHook(loan);
    }

    /**
     * @dev hook to call before the approvals are set
     *
     * @param fulfiller         The address executing seaport
     * @param maximumSpent      The maximumSpent asses we've received with the order
     * @param context           The abi encoded context we've received with the order
     */
    function _beforeApprovalsSetHook(address fulfiller, SpentItem[] calldata maximumSpent, bytes calldata context)
        internal
        virtual
    {}

    /**
     * @dev  hook to call before the loan get settlement call
     *
     * @param loan              The loan being settled
     */
    function _beforeGetSettlement(LoanManager.Loan memory loan) internal virtual {}

    /**
     * @dev  hook to call after the loan get settlement call
     *
     *
     * @param loan              The loan being settled
     */
    function _afterGetSettlement(LoanManager.Loan memory loan) internal virtual {}
    /**
     * @dev  hook to call before the the loan settlement handler execute call
     *
     * @param loan              The loan being settled
     */
    function _beforeSettlementHandlerHook(LoanManager.Loan memory loan) internal virtual {}

    /**
     * @dev  hook to call after the the loan settlement handler execute call
     *
     *
     * @param loan              The loan being settled
     */
    function _afterSettlementHandlerHook(LoanManager.Loan memory loan) internal virtual {}

    /**
     * @dev  hook to call before the loan is settled with the LM
     *
     * @param loan              The loan being settled
     */
    function _beforeSettleLoanHook(LoanManager.Loan memory loan) internal virtual {}

    /**
     * @dev  hook to call after the loan is settled with the LM
     *
     * @param loan              The loan being settled
     */
    function _afterSettleLoanHook(LoanManager.Loan memory loan) internal virtual {}
}
