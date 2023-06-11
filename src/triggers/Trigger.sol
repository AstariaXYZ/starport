pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

abstract contract Trigger {
  function isLoanHealthy(
    LoanManager.Loan calldata loan
  ) external view virtual returns (bool);
}
