pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

abstract contract Trigger {
  function isLoanHealthy(
    LoanManager.Loan calldata loan
  ) external view virtual returns (bool);
}

contract FixedTermTrigger is Trigger {
  struct Details {
    uint256 loanDuration;
  }

  function isLoanHealthy(
    LoanManager.Loan calldata loan
  ) external view override returns (bool) {
    Details memory details = abi.decode(loan.pricingData, (Details));
    return loan.start + details.loanDuration < block.timestamp;
  }
}
