pragma solidity ^0.8.17;

import {LenderEnforcer} from "starport-core/enforcers/LenderEnforcer.sol";
import {AdditionalTransfer} from "starport-core/lib/StarPortLib.sol";
import {Starport} from "starport-core/Starport.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import "forge-std/console2.sol";

contract AstariaV1LenderEnforcer is LenderEnforcer {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    error LoanAmountExceedsMaxAmount();
    error LoanAmountExceedsMaxRate();
    error InterestAccrualRoundingMinimum();

    int256 constant MAX_SIGNED_INT = 2 ** 255 - 1;
    uint256 constant MAX_UNSIGNED_INT = 2 ** 256 - 1;

    uint256 constant MAX_AMOUNT = 1e27; // 1_000_000_000 ether
    uint256 constant MAX_COMBINED_RATE_AND_DURATION = MAX_UNSIGNED_INT / MAX_AMOUNT;
    int256 constant MAX_DURATION = int256(3 * 365 * 1 days); // 3 years
    // int256 immutable MAX_RATE = int256(MAX_COMBINED_RATE_AND_DURATION).lnWad() / MAX_DURATION; // 780371100103 (IPR),  24.609783012848208000 (WAD), 2460.9783012848208000% (Percentage APY)
    int256 constant MAX_RATE = int256(780371100103);

    function validate(
        AdditionalTransfer[] calldata additionalTransfers,
        Starport.Loan calldata loan,
        bytes calldata caveatData
    ) public view virtual override {
        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));

        if (loan.debt[0].amount > MAX_AMOUNT) {
            revert LoanAmountExceedsMaxAmount();
        }

        if (pricingDetails.rate > uint256(MAX_SIGNED_INT) || int256(pricingDetails.rate) > MAX_RATE) {
            revert LoanAmountExceedsMaxRate();
        }

        // calculate interest for 1 second of time
        uint256 interest = StarPortLib.calculateCompoundInterest(1, loan.debt[0].amount, pricingDetails.rate);
        if (interest == 0) {
            // interest does not accrue at least 1 wei per second
            revert InterestAccrualRoundingMinimum();
        }
        super.validate(additionalTransfers, loan, caveatData);
    }
}
