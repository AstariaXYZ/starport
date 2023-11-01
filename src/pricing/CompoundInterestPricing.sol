pragma solidity ^0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {BaseRecallPricing} from "starport-core/pricing/BaseRecallPricing.sol";

abstract contract CompoundInterestPricing is BaseRecallPricing {
    using FixedPointMathLib for uint256;

    function calculateInterest(
        uint256 delta_t,
        uint256 amount,
        uint256 rate // expressed as SPR seconds per rate
    ) public pure override returns (uint256) {
        return (delta_t * rate).mulWad(amount);
    }
}
