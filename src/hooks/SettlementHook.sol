pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

abstract contract SettlementHook {
  function isActive(
    LoanManager.Loan calldata loan
  ) external virtual returns (bool);
}
