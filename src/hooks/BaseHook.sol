pragma solidity =0.8.17;

import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";
import {LoanManager} from "starport-core/LoanManager.sol";

abstract contract BaseHook is SettlementHook {
    function isRecalled(LoanManager.Loan calldata loan) external view virtual returns (bool);
}
