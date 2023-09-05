pragma solidity =0.8.17;

import {BasePricing} from "src/pricing/BasePricing.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LoanManager} from "src/LoanManager.sol";
import {Pricing} from "src/pricing/Pricing.sol";

contract SimpleInterestPricing is BasePricing {
  using FixedPointMathLib for uint256;

  constructor(LoanManager LM_) Pricing(LM_) {}
  function calculateInterest(
    uint256 delta_t,
    uint256 amount,
    uint256 rate // expressed as SPR seconds per rate
  ) public pure override returns (uint256) {
    return (delta_t * rate).mulWad(amount);
  }
}
