pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {Status} from "starport-core/status/Status.sol";

contract FixedTermStatus is Status {
    struct Details {
        uint256 loanDuration;
    }

    function isActive(Starport.Loan calldata loan, bytes calldata extraData) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.statusData, (Details));
        return loan.start + details.loanDuration > block.timestamp;
    }
}
