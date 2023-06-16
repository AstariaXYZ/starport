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

    ConsiderationInterface consideration;
    address public constant ENGLISH_AUCTION_ZONE = 0x110b2B128A9eD1be5Ef3232D8e4E41640dF5c2Cd;

    error InvalidOrder();

    constructor(LoanManager LM_, ConsiderationInterface consideration_) SettlementHandler(LM_) {
        consideration = consideration_;
    }

    function execute(LoanManager.Loan calldata loan) external virtual override returns (bytes4 selector) {
        selector = SettlementHandler.execute.selector;
    }

    function getSettlement(LoanManager.Loan memory loan, SpentItem[] calldata maximumSpent)
        external
        view
        override
        returns (ReceivedItem[] memory consideration, address restricted)
    {
        return (new ReceivedItem[](0), address(this));
    }

    function liquidate(LoanManager.Loan calldata loan) external {
        OrderParameters memory op = OrderParameters({
            offerer: address(LM.custodian()),
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

        AdvancedOrder memory x =
            AdvancedOrder({parameters: op, numerator: 1, denominator: 1, signature: "0x", extraData: abi.encode(loan)});

        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(this)
        });

        Details memory details = abi.decode(loan.terms.handlerData, (Details));
        uint256[] memory owing = Pricing(loan.terms.pricing).getOwed(loan);

        if (owing[0] < details.reservePrice) {
            owing[0] = details.reservePrice;
        }
        //check the loan debt type and set the order type based on that

        OfferItem[] memory offerItems = new OfferItem[](loan.collateral.length);
        //convert offer items from spent items
        uint256 i = 0;
        for (; i < loan.collateral.length;) {
            offerItems[i] = OfferItem({
                itemType: loan.collateral[i].itemType,
                token: loan.collateral[i].token,
                identifierOrCriteria: loan.collateral[i].identifier,
                startAmount: loan.collateral[i].amount,
                endAmount: loan.collateral[i].amount
            });
            unchecked {
                ++i;
            }
        }
        ConsiderationItem[] memory considerations = new ConsiderationItem[](
      loan.debt.length
    );
        for (; i < loan.debt.length;) {
            considerations[i] = ConsiderationItem({
                itemType: loan.debt[i].itemType,
                token: loan.debt[i].token,
                identifierOrCriteria: loan.debt[i].identifier,
                startAmount: loan.debt[i].amount,
                endAmount: loan.debt[i].amount,
                recipient: payable(LM.ownerOf(uint256(keccak256(abi.encode(loan)))))
            });
            unchecked {
                ++i;
            }
        }

        op = OrderParameters({
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
    }
}
