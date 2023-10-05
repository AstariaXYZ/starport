pragma solidity =0.8.17;

import {
    ItemType,
    OfferItem,
    SpentItem,
    ReceivedItem,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {Originator} from "starport-core/originators/Originator.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LoanManager, SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";

import {ConduitHelper} from "starport-core/ConduitHelper.sol";
import "forge-std/console2.sol";

abstract contract DutchAuctionHandler is SettlementHandler, AmountDeriver, ConduitHelper {
    constructor(LoanManager LM_) SettlementHandler(LM_) {
        LM = LM_;
    }

    using FixedPointMathLib for uint256;

    error InvalidAmount();

    struct Details {
        uint256 startingPrice;
        uint256 endingPrice;
        uint256 window;
    }

    function _getAuctionStart(LoanManager.Loan memory loan) internal view virtual returns (uint256);

    function getSettlement(LoanManager.Loan calldata loan)
        public
        view
        virtual
        override
        returns (ReceivedItem[] memory consideration, address restricted)
    {
        Details memory details = abi.decode(loan.terms.handlerData, (Details));
        uint256 settlementPrice;

        uint256 start = _getAuctionStart(loan);

        // DutchAuction has failed
        if (start + details.window < block.timestamp) {
            return (new ReceivedItem[](0), loan.issuer);
        }

        settlementPrice = _locateCurrentAmount({
            startAmount: details.startingPrice,
            endAmount: details.endingPrice,
            startTime: start,
            endTime: start + details.window,
            roundUp: true
        });

        (ReceivedItem[] memory paymentConsiderations, ReceivedItem[] memory carryFeeConsideration) =
            Pricing(loan.terms.pricing).getPaymentConsideration(loan);

        if (paymentConsiderations[0].amount <= settlementPrice) {
            carryFeeConsideration = new ReceivedItem[](0);
        } else {
            carryFeeConsideration[0].amount =
                settlementPrice - paymentConsiderations[0].amount - carryFeeConsideration[0].amount;
        }
        paymentConsiderations[0].amount = settlementPrice;

        consideration = _mergeConsiderations(paymentConsiderations, carryFeeConsideration, new ReceivedItem[](0));
        consideration = _removeZeroAmounts(consideration);
    }

    function validate(LoanManager.Loan calldata loan) external view virtual override returns (bool) {
        Details memory details = abi.decode(loan.terms.handlerData, (Details));
        return details.startingPrice > details.endingPrice;
    }
}
