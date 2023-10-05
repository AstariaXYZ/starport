pragma solidity =0.8.17;

import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {LoanManager} from "starport-core/LoanManager.sol";

contract FixedRateEnforcer is CaveatEnforcer {
    struct Details {
        uint256 maxRate;
        uint256 maxCarryRate;
    }

    function enforceCaveat(
        bytes calldata caveatTerms, //enforce theis
        LoanManager.Loan memory loan
    ) public view override returns (bool) {
        //lower and upper bounds
        Details memory caveatDetails = abi.decode(caveatTerms, (Details));

        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        return (caveatDetails.maxRate > details.rate && caveatDetails.maxCarryRate > details.carryRate);
    }
}
