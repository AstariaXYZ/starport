pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import "forge-std/console.sol";
import "seaport/lib/seaport-sol/src/lib/ReceivedItemLib.sol";
import {PoolHook} from "src/hooks/PoolHook.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract PoolPricing is Pricing {
  using FixedPointMathLib for uint256;
  LoanManager LM;
  error RefinanceNotAllowed();

  struct Details {
    uint256 deltaPrice;
  }

  constructor(LoanManager LM_) Pricing(LM_) {
    LM = LM_;
  }

  function getPaymentConsideration(
    LoanManager.Loan memory loan
  ) public view override virtual returns (ReceivedItem[] memory, ReceivedItem[] memory){
    Details memory details = abi.decode(loan.terms.pricingData, (Details));
    PoolHook.Details memory hookDetails = abi.decode(loan.terms.hookData, (PoolHook.Details));
    uint256 initialPrice = loan.collateral[0].amount.divWad(loan.debt[0].amount);
    uint256 amount;
    {
      uint256 delta_t = block.timestamp - loan.start;
      uint256 interest = delta_t.divWad(hookDetails.duration).mulWad(details.deltaPrice);

      amount = loan.debt[0].amount + interest;
    }
    ReceivedItem[] memory repaymentConsideration = new ReceivedItem[](1);
    repaymentConsideration[0] = ReceivedItem({
      itemType: loan.debt[0].itemType,
      token: loan.debt[0].token,
      identifier: 0,
      amount: amount,
      recipient: payable(loan.issuer)
    });
    return (repaymentConsideration, new ReceivedItem[](0));
  }

  function isValidRefinance(
    LoanManager.Loan memory loan,
    bytes memory newPricingData,
    address caller
  )
    external
    view
    override
    virtual
    returns (
      ReceivedItem[] memory,
      ReceivedItem[] memory,
      ReceivedItem[] memory
    ){
      revert RefinanceNotAllowed();
    }
}