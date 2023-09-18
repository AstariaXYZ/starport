pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";

contract PoolHook is SettlementHook {

  struct Details {
    uint256 duration;
  }
  function isActive(
    LoanManager.Loan calldata loan
  ) external view virtual returns (bool){
    Details memory details = abi.decode(loan.terms.hookData, (Details));
    return block.timestamp < loan.start + details.duration;
  }
}
