pragma solidity =0.8.17;

import {BaseEnforcer} from "starport-core/enforcers/BaseEnforcer.sol";
import {ConduitTransfer} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
contract BorrowerEnforcer is BaseEnforcer {

  error BorrowerOnlyEnforcer();

  function validate(ConduitTransfer[] calldata additionalTransfers, LoanManager.Loan calldata loan, bytes calldata caveatData) public view virtual override {
    bytes32 loanHash = keccak256(abi.encode(loan));

    Details memory details = abi.decode(caveatData, (Details));
    if(details.loan.borrower != loan.borrower) revert BorrowerOnlyEnforcer();
    details.loan.issuer = loan.issuer;
    // details.loan.start = block.timestamp;

    if(loanHash != keccak256(abi.encode(details.loan))) revert InvalidLoanTerms();

    if(additionalTransfers.length > 0) revert InvalidAdditionalTransfer();
  }
}