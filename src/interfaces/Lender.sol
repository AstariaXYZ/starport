pragma solidity =0.8.17;

import "src/LoanManager.sol";

abstract contract Lender {
  function onSettle(
    LoanManager.Loan calldata loan
  ) external virtual returns (bytes4 selector) {
    selector = Lender.onSettle.selector;
  }
}
