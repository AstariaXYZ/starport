pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {BaseRecallPricing} from "starport-core/pricing/BaseRecallPricing.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";

abstract contract CompoundInterestPricing is BaseRecallPricing {
    function calculateInterest(
        uint256 delta_t,
        uint256 amount,
        uint256 rate // expressed as SPR seconds per rate
    ) public pure override returns (uint256) {
        // return (delta_t * rate).mulWad(amount);
        return StarPortLib.calculateCompoundInterest(delta_t, amount, rate);
    }
}
