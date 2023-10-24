pragma solidity =0.8.17;

import {BaseEnforcer} from "starport-core/BaseEnforcer.sol";
import {ConduitTransfer} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
contract LenderEnforcer is BaseEnforcer {

  error LenderOnlyEnforcer();

  function validate(ConduitTransfer[] calldata additionalTransfers, LoanManager.Loan calldata loan, bytes calldata caveat) public view virtual override {
    bytes32 loanHash = keccak256(abi.encode(loan));

    Details memory details = abi.decode(caveat, (Details));
    if(details.loan.issuer != loan.issuer) revert LenderOnlyEnforcer();
    details.loan.borrower = loan.borrower;

    if(loanHash != keccak256(abi.encode(details.loan))) revert InvalidLoanTerms();

    if(additionalTransfers.length > 0) {
      uint256 i=0;
      for(;i<additionalTransfers.length;){
        if(additionalTransfers[i].from == loan.issuer) revert InvalidAdditionalTransfer();
        unchecked {
          ++i;
        }
      }
    }
  }
}