pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {Trigger} from "src/triggers/Trigger.sol";

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
