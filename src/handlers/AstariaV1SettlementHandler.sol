pragma solidity =0.8.17;

import {LoanManager, SpentItem, ReceivedItem, SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";
import {BaseHook} from "starport-core/hooks/BaseHook.sol";
import {BaseRecall} from "starport-core/hooks/BaseRecall.sol";
import {DutchAuctionHandler} from "starport-core/handlers/DutchAuctionHandler.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";

contract AstariaV1SettlementHandler is DutchAuctionHandler {
    using {StarPortLib.getId} for LoanManager.Loan;
    using FixedPointMathLib for uint256;

    constructor(LoanManager LM_) DutchAuctionHandler(LM_) {}

    function _getAuctionStart(LoanManager.Loan memory loan) internal view virtual override returns (uint256) {
        (, uint64 start) = BaseRecall(loan.terms.hook).recalls(loan.getId());
        BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
        return start + details.recallWindow + 1;
    }

    function getSettlement(LoanManager.Loan calldata loan)
        public
        view
        virtual
        override
        returns (ReceivedItem[] memory consideration, address restricted)
    {
        (address recaller,) = BaseRecall(loan.terms.hook).recalls(loan.getId());

        if (recaller == loan.issuer) {
            return (new ReceivedItem[](0), recaller);
        }

        uint256 start = _getAuctionStart(loan);
        Details memory details = abi.decode(loan.terms.handlerData, (Details));

        // DutchAuction has failed, give the NFT back to the lender (if they want it 😐)
        if (start + details.window < block.timestamp) {
            return (new ReceivedItem[](0), loan.issuer);
        }

        // DutchAuction price for anyone to bid on
        uint256 settlementPrice = _locateCurrentAmount({
            startAmount: details.startingPrice,
            endAmount: details.endingPrice,
            startTime: start,
            endTime: start + details.window,
            roundUp: true
        });

        (ReceivedItem[] memory paymentConsiderations, ReceivedItem[] memory carryFeeConsideration) =
            Pricing(loan.terms.pricing).getPaymentConsideration(loan);

        // the settlementPrice does not cover carryFees
        if (paymentConsiderations[0].amount <= settlementPrice) {
            carryFeeConsideration = new ReceivedItem[](0);
        }
        // the settlementPrice covers at least some of the carry fees
        else {
            carryFeeConsideration[0].amount =
                settlementPrice - paymentConsiderations[0].amount - carryFeeConsideration[0].amount;
        }
        paymentConsiderations[0].amount = settlementPrice;
        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.hookData, (BaseRecall.Details));

        uint256 recallerReward = paymentConsiderations[0].amount.mulWad(hookDetails.recallerRewardRatio);

        // recallerReward is taken directly from the repayment, carry is not subject to the recallerReward
        paymentConsiderations[0].amount -= recallerReward;
        ReceivedItem[] memory recallerPayment = new ReceivedItem[](1);
        recallerPayment[0] = ReceivedItem({
            itemType: paymentConsiderations[0].itemType,
            identifier: paymentConsiderations[0].identifier,
            amount: recallerReward,
            token: paymentConsiderations[0].token,
            recipient: payable(recaller)
        });

        consideration = _mergeConsiderations(paymentConsiderations, carryFeeConsideration, recallerPayment);
        consideration = _removeZeroAmounts(consideration);
    }

    function validate(LoanManager.Loan calldata loan) external view virtual override returns (bool) {
        return true;
    }
}
