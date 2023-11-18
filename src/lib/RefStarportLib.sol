// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

enum Actions {
    Nothing,
    Origination,
    Refinance,
    Repayment,
    Settlement
}

library RefStarportLib {
    error InvalidSalt();

    function validateSalt(
        mapping(address => mapping(bytes32 => bool)) storage usedSalts,
        address borrower,
        bytes32 salt
    ) internal {
        if (usedSalts[borrower][salt]) {
            revert InvalidSalt();
        }
        usedSalts[borrower][salt] = true;
    }
}
