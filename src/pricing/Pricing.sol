pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import "forge-std/console.sol";

abstract contract Pricing {
  LoanManager LM;

  constructor(LoanManager LM_) {
    LM = LM_;
  }

  function getPaymentConsideration(
    LoanManager.Loan calldata loan
  ) external view virtual returns (ReceivedItem[] memory consideration);

  function _generateRepayLenderConsideration(
    LoanManager.Loan calldata loan
  ) internal virtual returns (ReceivedItem[] memory consideration) {}
}
