pragma solidity =0.8.17;

import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {LoanManager} from "src/LoanManager.sol";

abstract contract BaseHook is SettlementHook {
  function isRecalled(
    LoanManager.Loan calldata loan
  ) external view virtual returns (bool);
}
