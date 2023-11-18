// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";

abstract contract CaveatEnforcer {
    struct Caveat {
        address enforcer;
        bytes data;
    }

    struct SignedCaveats {
        bool singleUse;
        uint256 deadline;
        bytes32 salt;
        Caveat[] caveats;
        bytes signature;
    }

    /**
     * @dev Enforces that the loan terms are identical except for the issuer
     * @param solution              The additional transfers to be made
     * @param loan                  The loan terms
     * @param caveatData            The borrowers encoded details
     */
    function validate(AdditionalTransfer[] calldata solution, Starport.Loan calldata loan, bytes calldata caveatData)
        public
        view
        virtual;
}
