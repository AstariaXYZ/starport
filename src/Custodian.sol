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

contract Custodian is ContractOffererInterface, TokenReceiverInterface, ConduitHelper {
    using {StarPortLib.getId} for LoanManager.Loan;

    LoanManager public immutable LM;
    address public immutable seaport;

    event SeaportCompatibleContractDeployed();

    error InvalidSender();
    error InvalidHandler();

    constructor(LoanManager LM_, address seaport_) {
        seaport = seaport_;
        LM = LM_;
        emit SeaportCompatibleContractDeployed();
    }

    //MODIFIERS

    modifier onlySeaport() {
        if (msg.sender != address(seaport)) {
            revert InvalidSender();
        }
        _;
    }

    //EXTERNAL FUNCTIONS

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
        LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
        //ensure loan is valid against what we have to deliver to seaport

        // we burn the loan on repayment in generateOrder, but in ratify order where we would trigger any post settlement actions
        // we burn it here so that in the case it was minted and an owner is set for settlement their pointer can still be utilized
        // in this case we are not a repayment we have burnt the loan in the generate order for a repayment
        uint256 loanId = loan.getId();
        if (LM.active(loanId)) {
            if (SettlementHandler(loan.terms.handler).execute(loan) != SettlementHandler.execute.selector) {
                revert InvalidHandler();
            }

            if (loan.issuer.code.length > 0) {
                //callback on the issuer
                //if supportsInterface() then do this
            }
            _settleLoan(loan);
        }
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
        (offer, consideration) = _fillObligationAndVerify(fulfiller, maximumSpent, context, true);
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
        function(
            address,
            SpentItem[] calldata,
            bytes calldata,
            bool
        ) internal view returns (SpentItem[] memory, ReceivedItem[] memory) fn;
        function(
            address,
            SpentItem[] calldata,
            bytes calldata,
            bool
        )
        internal
        returns (
            SpentItem[] memory,
            ReceivedItem[] memory
        ) fn2 = _fillObligationAndVerify;
        assembly {
            fn := fn2
        }

        (offer, consideration) = fn(fulfiller, maximumSpent, context, false);
    }

    function getBorrower(LoanManager.Loan memory loan) public view virtual returns (address) {
        return loan.borrower;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ContractOffererInterface)
        returns (bool)
    {
        return interfaceId == type(ContractOffererInterface).interfaceId;
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

    function _fillObligationAndVerify(
        address fulfiller,
        SpentItem[] calldata maximumSpent,
        bytes calldata context,
        bool withEffects
    ) internal returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        LoanManager.Loan memory loan = abi.decode(context, (LoanManager.Loan));
        offer = loan.collateral;

        if (SettlementHook(loan.terms.hook).isActive(loan)) {
            if (fulfiller != loan.borrower) {
                revert InvalidSender();
            }

            (ReceivedItem[] memory paymentConsiderations, ReceivedItem[] memory carryFeeConsideration) =
                Pricing(loan.terms.pricing).getPaymentConsideration(loan);

            consideration = _mergeConsiderations(paymentConsiderations, carryFeeConsideration, new ReceivedItem[](0));
            consideration = _removeZeroAmounts(consideration);

            //if a callback is needed for the issuer do it here
            if (withEffects) {
                _settleLoan(loan);
            }
        } else {
            address restricted;
            //add in originator fee
            if (withEffects) {
                _beforeSettlementHandlerHook(loan);
                (consideration, restricted) = SettlementHandler(loan.terms.handler).getSettlement(loan);
                _afterSettlementHandlerHook(loan);
            } else {
                (consideration, restricted) = SettlementHandler(loan.terms.handler).getSettlement(loan);
            }

            //TODO: remove and revert in get settlement if needed
            if (restricted != address(0) && fulfiller != restricted) {
                revert InvalidSender();
            }
        }

        if (offer.length > 0 && withEffects) {
            _beforeApprovalsSetHook(fulfiller, maximumSpent, context);
            _setOfferApprovals(offer, seaport);
        }
    }

    function _setOfferApprovals(SpentItem[] memory offer, address target) internal {
        for (uint256 i = 0; i < offer.length; i++) {
            //approve consideration based on item type
            if (offer[i].itemType == ItemType.ERC1155) {
                ERC1155(offer[i].token).setApprovalForAll(target, true);
            } else if (offer[i].itemType == ItemType.ERC721) {
                ERC721(offer[i].token).setApprovalForAll(target, true);
            } else if (offer[i].itemType == ItemType.ERC20) {
                uint256 allowance = ERC20(offer[i].token).allowance(address(this), target);
                if (allowance != 0) {
                    ERC20(offer[i].token).approve(target, 0);
                }
                ERC20(offer[i].token).approve(target, offer[i].amount);
            }
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

    function _beforeSettleLoanHook(LoanManager.Loan memory loan) internal virtual {}

    function _afterSettleLoanHook(LoanManager.Loan memory loan) internal virtual {}
}
