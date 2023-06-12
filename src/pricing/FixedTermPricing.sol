pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {Pricing} from "src/pricing/Pricing.sol";

contract FixedTermPricing is Pricing {
    struct Details {
        uint256 rate;
        uint256 loanDuration;
    }

    function getOwed(LoanManager.Loan calldata loan) public view override returns (uint256) {
        Details memory details = abi.decode(loan.pricingData, (Details));
        return _getOwed(loan, details, block.timestamp);
    }

    function _getOwed(LoanManager.Loan memory loan, Details memory details, uint256 timestamp)
        internal
        pure
        returns (uint256)
    {
        return loan.debt.amount * details.rate * (loan.start + details.loanDuration - timestamp);
    }
}
