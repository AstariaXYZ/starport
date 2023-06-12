pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract FixedTermPricing is Pricing {
  using FixedPointMathLib for uint256;

  constructor(LoanManager LM_) Pricing(LM_) {}

  struct Details {
    uint256 rate;
    uint256 loanDuration;
  }

  function getPaymentConsideration(
    LoanManager.Loan calldata loan
  ) external view virtual override returns (ReceivedItem memory consideration) {
    consideration = _generateRepayLenderConsideration(loan);
  }

  function getOwed(
    LoanManager.Loan calldata loan
  ) public view override returns (uint256) {
    Details memory details = abi.decode(loan.pricingData, (Details));
    return _getOwed(loan, details, block.timestamp);
  }

  function _getOwed(
    LoanManager.Loan memory loan,
    Details memory details,
    uint256 timestamp
  ) internal pure returns (uint256) {
    return loan.debt.amount + _getInterest(loan, details, timestamp);
  }

  function _getInterest(
    LoanManager.Loan memory loan,
    Details memory details,
    uint256 timestamp
  ) internal pure returns (uint256) {
    uint256 delta_t = timestamp - loan.start;

    return (delta_t * details.rate).mulWad(loan.debt.amount);
  }
}
