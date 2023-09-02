pragma solidity =0.8.17;
import {LoanManager} from "src/LoanManager.sol";
import {CompoundInterestPricing} from "src/pricing/CompoundInterestPricing.sol";
import {Pricing} from "src/pricing/Pricing.sol";
contract AstariaV1Pricing is CompoundInterestPricing {
  constructor(LoanManager LM_) Pricing(LM_) {}
}

