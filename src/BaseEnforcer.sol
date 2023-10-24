pragma solidity =0.8.17;

import {Enforcer} from "starport-core/Enforcer.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
import {ConduitTransfer} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
contract BaseEnforcer is Enforcer{

  error InvalidLoanTerms();
  error InvalidAdditionalTransfer();

  struct Details {
    LoanManager.Loan loan;
  }
  
  function validate(ConduitTransfer[] calldata additionalTransfers, LoanManager.Loan calldata loan, bytes calldata caveat) public view virtual override {
    bytes32 loanHash = keccak256(abi.encode(loan));

    Details memory details = abi.decode(caveat, (Details));
    details.loan.start = block.timestamp;

    if(loanHash != keccak256(abi.encode(details.loan))) revert InvalidLoanTerms();

    if(additionalTransfers.length > 0) revert InvalidAdditionalTransfer();
  }
}