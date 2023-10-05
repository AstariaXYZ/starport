pragma solidity =0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";
import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";

contract FixedTermHook is SettlementHook {
    struct Details {
        uint256 loanDuration;
    }

    function isActive(LoanManager.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        return loan.start + details.loanDuration > block.timestamp;
    }
}
