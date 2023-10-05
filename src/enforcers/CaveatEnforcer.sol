pragma solidity =0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";

abstract contract CaveatEnforcer {
    function enforceCaveat(bytes calldata terms, LoanManager.Loan memory loan) public virtual returns (bool);
}
