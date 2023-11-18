// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {Status} from "starport-core/status/Status.sol";
import {Validation} from "starport-core/lib/Validation.sol";

contract FixedTermStatus is Status {
    struct Details {
        uint256 loanDuration;
    }

    // @inheritdoc Status
    function isActive(Starport.Loan calldata loan, bytes calldata extraData) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.statusData, (Details));
        return loan.start + details.loanDuration > block.timestamp;
    }

    function validate(Starport.Loan calldata loan) external view override returns (bytes4) {
        Details memory details = abi.decode(loan.terms.statusData, (Details));
        return (details.loanDuration > 0) ? Validation.validate.selector : bytes4(0xFFFFFFFF);
    }
}
