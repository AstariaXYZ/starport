pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract Pricing {
  LoanManager LM;

  constructor(LoanManager LM_) {
    LM = LM_;
  }

  uint x;

  function getPaymentConsideration(
    LoanManager.Loan calldata loan
  ) external view virtual returns (ReceivedItem memory consideration);

  function getOwed(
    LoanManager.Loan calldata loan
  ) public view virtual returns (uint256);

  function _generateRepayLenderConsideration(
    LoanManager.Loan calldata loan
  ) internal view returns (ReceivedItem memory consideration) {
    consideration = loan.debt;
    consideration.amount = getOwed(loan);
    consideration.recipient = payable(
      LM.ownerOf(uint256(keccak256(abi.encode(loan))))
    );
  }
}
