pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {BasePricing} from "src/pricing/BasePricing.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {BaseRecallPricing} from "src/pricing/BaseRecallPricing.sol";

abstract contract CompoundInterestPricing is BaseRecallPricing {
  using FixedPointMathLib for uint256;

  // function getInterest(
  //   uint256 delta_t,
  //   uint256 amount,
  //   uint256 rate // expressed as SPR seconds per rate
  // ) public pure override returns (uint256) {
  //   return amount.mulWad((2718281828459045235 ** rate.mulWad(delta_t)) / 1e18);
  // }
  function calculateInterest(
    uint256 delta_t,
    uint256 amount,
    uint256 rate // expressed as SPR seconds per rate
  ) public pure override returns (uint256) {
    return (delta_t * rate).mulWad(amount);
  }
}
