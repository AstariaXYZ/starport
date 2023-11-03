pragma solidity ^0.8.17;

import {AdditionalTransfer} from "starport-core/lib/StarPortLib.sol";
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

    function validate(AdditionalTransfer[] calldata solution, Starport.Loan calldata loan, bytes calldata caveatData)
        public
        view
        virtual;
}
