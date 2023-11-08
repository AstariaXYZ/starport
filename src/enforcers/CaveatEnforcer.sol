pragma solidity ^0.8.17;

import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";
import {Starport} from "starport-core/Starport.sol";

abstract contract CaveatEnforcer {
    struct Caveat {
        address enforcer;
        uint256 deadline;
        bytes data;
    }

    struct CaveatWithApproval {
        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes32 salt;
        Caveat[] caveat;
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
