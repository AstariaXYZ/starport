// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";

import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract Originator {
    struct Request {
        address borrower;
        CaveatEnforcer.SignedCaveats borrowerCaveat;
        SpentItem[] collateral;
        SpentItem[] debt;
        bytes details;
        bytes approval;
    }

    /**
     * @dev Accepts a request with signed data that is decoded by the originator
     * communicates with Starport to originate a loan
     * @param params          The request for the origination
     */
    function originate(Request calldata params) external virtual;
}
