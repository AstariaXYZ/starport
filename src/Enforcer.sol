pragma solidity =0.8.17;
// import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConduitTransfer} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
abstract contract Enforcer {

  struct Caveat {
    address enforcer;
    bytes32 salt;
    bytes caveat;
    Approval approval;
  }

  struct Approval {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  function validate(ConduitTransfer[] calldata solution, LoanManager.Loan calldata loan, bytes calldata caveat) public view virtual;
}