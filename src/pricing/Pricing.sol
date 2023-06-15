pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import "forge-std/console.sol";

abstract contract Pricing {
  LoanManager LM;

  constructor(LoanManager LM_) {
    LM = LM_;
  }

  uint x;

  function getPaymentConsideration(
    LoanManager.Loan calldata loan
  ) external view virtual returns (ReceivedItem[] memory consideration);

  function getOwed(
    LoanManager.Loan calldata loan
  ) public view virtual returns (uint256[] memory);

  function _generateRepayLenderConsideration(
    LoanManager.Loan calldata loan
  ) internal view virtual returns (ReceivedItem[] memory consideration) {
    consideration = new ReceivedItem[](loan.debt.length);
    uint256[] memory owing = getOwed(loan);
    address payable lender = payable(
      LM.ownerOf(uint256(keccak256(abi.encode(loan))))
    );
    uint256 i = 0;
    for (; i < loan.debt.length; ) {
      consideration[i] = ReceivedItem({
        itemType: loan.debt[i].itemType,
        identifier: loan.debt[i].identifier,
        amount: owing.length == consideration.length ? owing[i] : owing[0],
        token: loan.debt[i].token,
        recipient: lender
      });
      unchecked {
        ++i;
      }
    }
  }
}
