pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import "forge-std/console.sol";
import "seaport/lib/seaport-sol/src/lib/ReceivedItemLib.sol";

abstract contract Pricing {
  LoanManager LM;

  error InvalidRefinance();

  constructor(LoanManager LM_) {
    LM = LM_;
  }

  function getPaymentConsideration(LoanManager.Loan memory loan)
    public
    view
    virtual
    returns (ReceivedItem[] memory, ReceivedItem[] memory);

  function isValidRefinance(LoanManager.Loan memory loan, bytes memory newPricingData, address caller)
    external
    view
    virtual
    returns (ReceivedItem[] memory, ReceivedItem[] memory, ReceivedItem[] memory);
}
