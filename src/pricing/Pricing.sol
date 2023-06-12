pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

abstract contract Pricing {
  function getOwed(
    LoanManager.Loan calldata loan
  ) public view virtual returns (uint256);
}
