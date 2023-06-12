pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {
    ItemType,
    OfferItem,
    Schema,
    SpentItem,
    ReceivedItem,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SettlementHandler} from "src/handlers/SettlementHandler.sol";
import {Consideration} from "seaport-core/src/lib/Consideration.sol";
import {
    ConsiderationItem,
    AdvancedOrder,
    Order,
    CriteriaResolver,
    OrderType
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Pricing} from "src/pricing/Pricing.sol";

contract EnglishAuctionHandler is SettlementHandler {
    struct Details {
        uint256 reservePrice;
        uint256 window;
    }

    LoanManager LM;
    ConsiderationInterface consideration;
    address public constant ENGLISH_AUCTION_ZONE = 0x110b2B128A9eD1be5Ef3232D8e4E41640dF5c2Cd;

    error InvalidOrder();

    constructor(LoanManager LM_, ConsiderationInterface consideration_) {
        LM = LM_;
        consideration = consideration_;
    }

    function execute(LoanManager.Loan calldata loan) external virtual override returns (bytes4) {
        Details memory details = abi.decode(loan.handlerData, (Details));
        uint256 owing = Pricing(loan.pricing).getOwed(loan);

        if (owing < details.reservePrice) {
            owing = details.reservePrice;
        }
        //check the loan debt type and set the order type based on that

        OfferItem[] memory offerItems = new OfferItem[](1);
        offerItems[0] = OfferItem({
            itemType: loan.collateral.itemType,
            token: loan.collateral.token,
            identifierOrCriteria: loan.collateral.identifier,
            startAmount: loan.collateral.amount,
            endAmount: loan.collateral.amount
        });
        ConsiderationItem[] memory considerations = new ConsiderationItem[](1);
        considerations[0] = ConsiderationItem({
            itemType: loan.debt.itemType,
            token: loan.debt.token,
            identifierOrCriteria: loan.debt.identifier,
            startAmount: details.reservePrice,
            endAmount: owing,
            recipient: loan.debt.recipient
        });

        OrderParameters memory op = OrderParameters({
            offerer: address(LM),
            zone: ENGLISH_AUCTION_ZONE,
            offer: offerItems,
            consideration: considerations,
            orderType: OrderType.FULL_RESTRICTED,
            startTime: block.timestamp + 1,
            endTime: block.timestamp + details.window,
            zoneHash: bytes32(0),
            salt: 0,
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: 1
        });

        Order memory order = Order({parameters: op, signature: "0x"});

        Order[] memory orders = new Order[](1);
        orders[0] = order;
        bool isValid = consideration.validate(orders);
        if (!isValid) {
            revert InvalidOrder();
        }
        return SettlementHandler.execute.selector;
    }

    function getSettlement(
        LoanManager.Loan memory loan,
        SpentItem[] calldata maximumSpent,
        uint256 owing,
        address payable lmOwner
    ) external view override returns (ReceivedItem[] memory consideration, address restricted) {
        return (new ReceivedItem[](0), address(this));
    }

    function liquidate(LoanManager.Loan calldata loan) external {
        OrderParameters memory op = OrderParameters({
            offerer: address(LM),
            zone: address(0),
            offer: new OfferItem[](0),
            consideration: new ConsiderationItem[](0),
            orderType: OrderType.CONTRACT,
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            zoneHash: bytes32(0),
            salt: 0,
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: 0
        });

        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(uint8(LoanManager.Action.UNLOCK), loan)
        });

        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(this)
        });
    }
}
