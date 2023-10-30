pragma solidity ^0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";
import {CompoundInterestPricing} from "starport-core/pricing/CompoundInterestPricing.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {AstariaV1SettlementHook} from "starport-core/hooks/AstariaV1SettlementHook.sol";

import {BaseRecall} from "starport-core/hooks/BaseRecall.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";

contract AstariaV1Pricing is CompoundInterestPricing {
    using FixedPointMathLib for uint256;
    using {StarPortLib.getId} for LoanManager.Loan;

    constructor(LoanManager LM_) Pricing(LM_) {}

    error InsufficientRefinance();

    function isValidRefinance(LoanManager.Loan memory loan, bytes memory newPricingData, address caller)
        external
        view
        virtual
        override
        returns (
            SpentItem[] memory repayConsideration,
            SpentItem[] memory carryConsideration,
            ConduitTransfer[] memory recallConsideration
        )
    {
        // borrowers can refinance a loan at any time
        if (caller != loan.borrower) {
            // check if a recall is occuring
            AstariaV1SettlementHook hook = AstariaV1SettlementHook(loan.terms.hook);
            Details memory newDetails = abi.decode(newPricingData, (Details));
            if (hook.isRecalled(loan)) {
                uint256 rate = hook.getRecallRate(loan);
                // offered loan did not meet the terms of the recall auction
                if (newDetails.rate > rate) revert InsufficientRefinance();
            }
            // recall is not occuring
            else {
                revert InvalidRefinance();
            }
            Details memory oldDetails = abi.decode(loan.terms.pricingData, (Details));

            uint256 proportion;
            address payable receiver = payable(loan.issuer);
            uint256 loanId = loan.getId();
            // scenario where the recaller is not penalized
            // recaller stake is refunded
            if (newDetails.rate > oldDetails.rate) {
                proportion = 1e18;
                (receiver,) = hook.recalls(loanId);
            } else {
                // scenario where the recaller is penalized
                // essentially the old lender and the new lender split the stake of the recaller
                // split is proportional to the difference in rate
                proportion = 1e18 - (oldDetails.rate - newDetails.rate).divWad(oldDetails.rate);
            }
            recallConsideration = hook.generateRecallConsideration(loan, proportion, caller, receiver);
        }

        (repayConsideration, carryConsideration) = getPaymentConsideration(loan);
    }
}
