pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console.sol";

contract FixedTermPricing is Pricing {
  using FixedPointMathLib for uint256;

  constructor(LoanManager LM_) Pricing(LM_) {}

  struct Details {
    uint256 rate;
    uint256 carryRate;
  }

  function getPaymentConsideration(
    LoanManager.Loan memory loan
  )
    public
    view
    virtual
    override
    returns (
      ReceivedItem[] memory repayConsideration,
      ReceivedItem[] memory carryConsideration
    )
  {
    repayConsideration = _generateRepayConsideration(loan);
    carryConsideration = _generateRepayCarryConsideration(loan);
  }

  function getOwed(
    LoanManager.Loan memory loan
  ) public view returns (uint256[] memory) {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));
    return _getOwed(loan, details, block.timestamp);
  }

  function _getOwedCarry(
    LoanManager.Loan memory loan,
    Details memory details,
    uint256 timestamp
  ) internal view returns (uint256[] memory carryOwed) {
    carryOwed = new uint256[](loan.debt.length);
    uint256 carryOwedAboveZero;
    uint256 i = 0;

    for (; i < loan.debt.length; ) {
      uint256 carry = _getInterest(loan, details, timestamp, i).mulWad(
        details.carryRate
      );
      if (carry > 0) {
        carryOwed[i] = carry;
        unchecked {
          ++carryOwedAboveZero;
        }
      }
      unchecked {
        ++i;
      }
    }

    if (carryOwedAboveZero != loan.debt.length) {
      assembly {
        mstore(carryOwed, carryOwedAboveZero)
      }
    }
  }

  function _getOwed(
    LoanManager.Loan memory loan,
    Details memory details,
    uint256 timestamp
  ) internal view returns (uint256[] memory updatedDebt) {
    updatedDebt = new uint256[](loan.debt.length);
    for (uint256 i = 0; i < loan.debt.length; i++) {
      updatedDebt[i] =
        loan.debt[i].amount +
        _getInterest(loan, details, timestamp, i);
    }
  }

  function _getInterest(
    LoanManager.Loan memory loan,
    Details memory details,
    uint256 timestamp,
    uint256 index
  ) internal view returns (uint256) {
    uint256 delta_t = timestamp - loan.start;

    return (delta_t * details.rate).mulWad(loan.debt[index].amount);
  }

  function _generateRepayConsideration(
    LoanManager.Loan memory loan
  ) internal view returns (ReceivedItem[] memory consideration) {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));

    consideration = new ReceivedItem[](loan.debt.length);
    uint256[] memory owing = _getOwed(loan, details, block.timestamp);
    address payable issuer = LM.getIssuer(loan);

    uint256 i = 0;
    for (; i < consideration.length; ) {
      consideration[i] = ReceivedItem({
        itemType: loan.debt[i].itemType,
        identifier: loan.debt[i].identifier,
        amount: owing.length == consideration.length ? owing[i] : owing[0],
        token: loan.debt[i].token,
        recipient: payable(issuer)
      });
      unchecked {
        ++i;
      }
    }
  }

  function _generateRepayCarryConsideration(
    LoanManager.Loan memory loan
  ) internal view returns (ReceivedItem[] memory consideration) {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));

    uint256[] memory owing = _getOwedCarry(loan, details, block.timestamp);
    consideration = new ReceivedItem[](owing.length);
    uint256 i = 0;
    for (; i < consideration.length; ) {
      consideration[i] = ReceivedItem({
        itemType: loan.debt[i].itemType,
        identifier: loan.debt[i].identifier,
        amount: owing.length == consideration.length ? owing[i] : owing[0],
        token: loan.debt[i].token,
        recipient: payable(loan.originator)
      });
      unchecked {
        ++i;
      }
    }
  }

  function isValidRefinance(
    LoanManager.Loan memory loan,
    bytes memory newPricingData
  )
    external
    view
    override
    returns (ReceivedItem[] memory, ReceivedItem[] memory)
  {
    Details memory oldDetails = abi.decode(loan.terms.pricingData, (Details));
    Details memory newDetails = abi.decode(newPricingData, (Details));
    bool active = SettlementHook(loan.terms.hook).isActive(loan);

    //todo: figure out the proper flow for here
    if (
      (active && newDetails.rate >= oldDetails.rate) ||
      (!active && newDetails.rate <= oldDetails.rate)
    ) {
      revert InvalidRefinance();
    }
    return getPaymentConsideration(loan);
  }
}
