pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

abstract contract SettlementHook {
  function isActive(
    LoanManager.Loan calldata loan
  ) external view virtual returns (bool);

  function isRecalled(
    LoanManager.Loan calldata loan
  ) external virtual view returns (bool);
}
