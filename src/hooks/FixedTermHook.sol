pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";

contract FixedTermHook is SettlementHook {
    struct Details {
        uint256 loanDuration;
    }

    function isActive(Starport.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.statusData, (Details));
        return loan.start + details.loanDuration > block.timestamp;
    }
}
