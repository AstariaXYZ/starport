pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";

import {BaseHook} from "src/hooks/BaseHook.sol";
import {StarPortLib} from "src/lib/StarPortLib.sol";

abstract contract BasePricing is Pricing {
  using FixedPointMathLib for uint256;
  using {StarPortLib.getId} for LoanManager.Loan;

  struct Details {
    uint256 rate;
    uint256 carryRate;
  }

  function getPaymentConsideration(LoanManager.Loan memory loan)
    public
    view
    virtual
    override
    returns (ReceivedItem[] memory repayConsideration, ReceivedItem[] memory carryConsideration)
  {
    repayConsideration = _generateRepayConsideration(loan);
    carryConsideration = _generateRepayCarryConsideration(loan);
  }

  function getOwed(LoanManager.Loan memory loan) public view returns (uint256[] memory) {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));
    return _getOwed(loan, details, loan.start, block.timestamp);
  }

  function _getOwedCarry(LoanManager.Loan memory loan, Details memory details, uint256 timestamp)
    internal
    view
    returns (uint256[] memory carryOwed)
  {
    carryOwed = new uint256[](loan.debt.length);
    uint256 i = 0;

    for (; i < loan.debt.length;) {
      uint256 carry = getInterest(loan, details, loan.start, timestamp, i).mulWad(details.carryRate);
      carryOwed[i] = carry;
      unchecked {
        ++i;
      }
    }
  }

  function _getOwed(LoanManager.Loan memory loan, Details memory details, uint256 start, uint256 end)
    internal
    view
    returns (uint256[] memory updatedDebt)
  {
    updatedDebt = new uint256[](loan.debt.length);
    for (uint256 i = 0; i < loan.debt.length; i++) {
      updatedDebt[i] = loan.debt[i].amount + getInterest(loan, details, start, end, i);
    }
  }

  function getInterest(LoanManager.Loan memory loan, Details memory details, uint256 start, uint256 end, uint256 index)
    public
    view
    returns (uint256)
  {
    uint256 delta_t = end - start;
    return calculateInterest(delta_t, details.rate, loan.debt[index].amount);
  }

  function calculateInterest(
    uint256 delta_t,
    uint256 amount,
    uint256 rate // expressed as SPR seconds per rate
  ) public pure virtual returns (uint256);

  function _generateRepayConsideration(LoanManager.Loan memory loan)
    internal
    view
    returns (ReceivedItem[] memory consideration)
  {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));

    consideration = new ReceivedItem[](loan.debt.length);
    uint256[] memory owing = _getOwed(loan, details, loan.start, block.timestamp);
    bool isActive = LM.active(loan.getId());

    uint256 i = 0;
    for (; i < consideration.length;) {
      consideration[i] = ReceivedItem({
        itemType: loan.debt[i].itemType,
        identifier: loan.debt[i].identifier,
        amount: owing[i],
        token: loan.debt[i].token,
        recipient: payable(loan.issuer)
      });
      unchecked {
        ++i;
      }
    }
  }

  function _generateRepayCarryConsideration(LoanManager.Loan memory loan)
    internal
    view
    returns (ReceivedItem[] memory consideration)
  {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));

    if (details.carryRate == 0) return new ReceivedItem[](0);
    uint256[] memory owing = _getOwedCarry(loan, details, block.timestamp);
    consideration = new ReceivedItem[](owing.length);
    uint256 i = 0;
    for (; i < consideration.length;) {
      consideration[i] = ReceivedItem({
        itemType: loan.debt[i].itemType,
        identifier: loan.debt[i].identifier,
        amount: owing[i],
        token: loan.debt[i].token,
        recipient: payable(loan.originator)
      });
      unchecked {
        ++i;
      }
    }
  }
}
