pragma solidity ^0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";
import {AdditionalTransfer} from "starport-core/lib/StarPortLib.sol";
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
import {SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";
import {Consideration} from "seaport-core/src/lib/Consideration.sol";
import {
    ConsiderationItem,
    AdvancedOrder,
    Order,
    CriteriaResolver,
    OrderType
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";

contract EnglishAuctionHandler is SettlementHandler {
    using FixedPointMathLib for uint256;

    struct Details {
        uint256[] reservePrice; // per debt item
        uint256 window;
    }

    ConsiderationInterface consideration;
    address public ENGLISH_AUCTION_ZONE;
    //    address public constant ENGLISH_AUCTION_ZONE = 0x110b2B128A9eD1be5Ef3232D8e4E41640dF5c2Cd;

    // opensea payment receiver

    address payable public constant OS_RECEIVER = payable(0x0000a26b00c1F0DF003000390027140000fAa719);

    error InvalidOrder();

    constructor(LoanManager LM_, ConsiderationInterface consideration_, address EAZone_) SettlementHandler(LM_) {
        consideration = consideration_;
        ENGLISH_AUCTION_ZONE = EAZone_;
    }

    //use when building offers to ensure the data works with the handler
    function validate(LoanManager.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.handlerData, (Details));
        return details.reservePrice.length == loan.debt.length;
    }

    function execute(LoanManager.Loan calldata loan, address fulfiller) external virtual override returns (bytes4) {
        if (fulfiller != address(this)) {
            revert("must liquidate via the handler to trigger english auction");
        }
        return SettlementHandler.execute.selector;
    }

    function getSettlement(LoanManager.Loan calldata loan)
        public
        view
        override
        returns (ReceivedItem[] memory consideration, address restricted)
    {
        return (new ReceivedItem[](0), address(this));
    }

    function liquidate(LoanManager.Loan calldata loan) external {
        OrderParameters memory op = OrderParameters({
            offerer: address(loan.custodian),
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
            recipient: address(0)
        });

        Details memory details = abi.decode(loan.terms.handlerData, (Details));
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
      loan.debt.length + 1
    );

        uint256 feeRake = uint256(25000000000000000);
        uint256 reserveRake;
        uint256 rake;

        i = 0;
        for (; i < loan.debt.length;) {
            rake = (loan.debt[i].amount * 2).mulWad(feeRake);
            reserveRake = details.reservePrice[i].mulWad(feeRake);
            considerations[i] = ConsiderationItem({
                itemType: loan.debt[i].itemType,
                token: loan.debt[i].token,
                identifierOrCriteria: loan.debt[i].identifier,
                startAmount: details.reservePrice[i] - reserveRake,
                endAmount: (loan.debt[i].amount * 2) - rake,
                recipient: payable(loan.issuer)
            });
            unchecked {
                ++i;
            }
        }

        considerations[considerations.length - 1] = ConsiderationItem({
            itemType: loan.debt[0].itemType,
            token: loan.debt[0].token,
            identifierOrCriteria: loan.debt[0].identifier,
            startAmount: reserveRake,
            endAmount: rake,
            recipient: OS_RECEIVER
        });

        op = OrderParameters({
            offerer: address(this),
            zone: ENGLISH_AUCTION_ZONE,
            offer: offerItems,
            consideration: considerations,
            orderType: OrderType.FULL_RESTRICTED,
            startTime: block.timestamp + 1,
            endTime: block.timestamp + details.window,
            zoneHash: bytes32(0),
            salt: 0,
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: 2
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
