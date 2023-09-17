pragma solidity ^0.8.0;

import {CaveatEnforcer} from "./CaveatEnforcer.sol";
import {LoanManager} from "src/LoanManager.sol";
import "forge-std/console.sol";

contract TermEnforcer is CaveatEnforcer {
  struct Details {
    address pricing;
    address hook;
    address handler;
  }

  function enforceCaveat(bytes calldata terms, LoanManager.Loan memory loan) public view override returns (bool valid) {
    Details memory details = abi.decode(terms, (Details));
    valid = true;

    console.log("enforcing term caveat");
    if (details.pricing != address(0)) {
      valid = valid && loan.terms.pricing == details.pricing;
    }
    if (details.hook != address(0)) {
      valid = valid && loan.terms.hook == details.hook;
    }
    if (details.handler != address(0)) {
      valid = valid && loan.terms.handler == details.handler;
    }
  }
}
