pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console.sol";

contract FixedTermPricing is Pricing {
  using FixedPointMathLib for uint256;

  constructor(LoanManager LM_) Pricing(LM_) {}

  struct Details {
    uint256 rate;
    uint256 loanDuration;
  }

  function getPaymentConsideration(
    LoanManager.Loan calldata loan
  )
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory consideration)
  {
    consideration = _generateRepayLenderConsideration(loan);
  }

  function getOwed(
    LoanManager.Loan calldata loan
  ) public view returns (uint256[] memory) {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));
    return _getOwed(loan, details, block.timestamp);
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
      console.log(updatedDebt[i]);
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

  function _generateRepayLenderConsideration(
    LoanManager.Loan calldata loan
  ) internal view override returns (ReceivedItem[] memory consideration) {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));

    consideration = new ReceivedItem[](loan.debt.length);
    uint256[] memory owing = _getOwed(loan, details, block.timestamp);
    address payable issuer = LM.getIssuer(loan);
    uint256 i = 0;
    for (; i < loan.debt.length; ) {
      consideration[i] = ReceivedItem({
        itemType: loan.debt[i].itemType,
        identifier: loan.debt[i].identifier,
        amount: owing.length == consideration.length ? owing[i] : owing[0],
        token: loan.debt[i].token,
        recipient: issuer
      });
      unchecked {
        ++i;
      }
    }
  }
}
