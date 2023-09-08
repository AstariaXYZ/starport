pragma solidity =0.8.17;
import {LoanManager} from "src/LoanManager.sol";
import {CompoundInterestPricing} from "src/pricing/CompoundInterestPricing.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {BasePricing} from "src/pricing/BasePricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {AstariaV1SettlementHook} from "src/hooks/AstariaV1SettlementHook.sol";

import {BaseRecall} from "src/hooks/BaseRecall.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
contract AstariaV1Pricing is CompoundInterestPricing {
  using FixedPointMathLib for uint256;
  constructor(LoanManager LM_) Pricing(LM_) {}

  function isValidRefinance(
    LoanManager.Loan memory loan,
    bytes memory newPricingData
  )
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory repayConsideration, ReceivedItem[] memory carryConsideration, ReceivedItem[] memory recallConsideration)
  {
    // check if a recall is occuring
    AstariaV1SettlementHook hook = AstariaV1SettlementHook(loan.terms.hook);
    Details memory newDetails = abi.decode(newPricingData, (Details));
    if(hook.isRecalled(loan)){
      uint256 rate = hook.getRecallRate(loan);
      // offered loan did not meet the terms of the recall auction
      if(newDetails.rate > rate) revert InvalidRefinance();
    }
    else revert InvalidRefinance();
    Details memory oldDetails = abi.decode(loan.terms.pricingData, (Details));

    uint256 proportion;
    address payable receiver = payable(loan.issuer);
    uint256 loanId = LM.getTokenIdFromLoan(loan);
    // scenario where the recaller is not penalized
    // recaller stake is refunded
    if(newDetails.rate > oldDetails.rate){
      proportion = 1e18;
      (receiver, ) = hook.recalls(loanId);
    }
    else {
      // scenario where the recaller is penalized
      // essentially the old lender and the new lender split the stake of the recaller
      // split is proportional to the difference in rate
      proportion = 1e18 - (oldDetails.rate - newDetails.rate).divWad(oldDetails.rate);
    }
    recallConsideration = hook.generateRecallConsideration(loan, proportion, receiver);
    (repayConsideration, carryConsideration) = getPaymentConsideration(loan);
  }
}

