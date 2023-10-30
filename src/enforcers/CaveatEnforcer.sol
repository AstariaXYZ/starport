pragma solidity =0.8.17;
// import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ConduitTransfer} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {LoanManager} from "starport-core/LoanManager.sol";

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

    function validate(ConduitTransfer[] calldata solution, LoanManager.Loan calldata loan, bytes calldata caveatData)
        public
        view
        virtual;
}
