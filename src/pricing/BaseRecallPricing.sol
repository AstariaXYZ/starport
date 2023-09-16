pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {BasePricing} from "src/pricing/BasePricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";

import {BaseHook} from "src/hooks/BaseHook.sol";
import {StarPortLib} from "src/lib/StarPortLib.sol";

abstract contract BaseRecallPricing is BasePricing {
    function isValidRefinance(LoanManager.Loan memory loan, bytes memory newPricingData, address caller)
        external
        view
        virtual
        override
        returns (
            ReceivedItem[] memory repayConsideration,
            ReceivedItem[] memory carryConsideration,
            ReceivedItem[] memory recallConsideration
        )
    {
        Details memory oldDetails = abi.decode(loan.terms.pricingData, (Details));
        Details memory newDetails = abi.decode(newPricingData, (Details));
        bool isRecalled = BaseHook(loan.terms.hook).isRecalled(loan);

        //todo: figure out the proper flow for here
        if ((isRecalled && newDetails.rate >= oldDetails.rate) || (newDetails.rate < oldDetails.rate)) {
            (repayConsideration, carryConsideration) = getPaymentConsideration(loan);
            recallConsideration = new ReceivedItem[](0);
        }
    }
}
