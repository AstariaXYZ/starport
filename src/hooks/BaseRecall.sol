pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";

abstract contract BaseRecall {
  LoanManager LM;
  mapping(uint256 => uint256) recalls;
  struct Details {
      uint256 minRecall;
      uint256 recallWindow;
  }

  function recall(LoanManager.Loan calldata loan) external returns (bool) {
    Details memory details = abi.decode(loan.terms.hookData, (Details));
    if(loan.start + details.minRecall < block.timestamp) {
      revert("recall below minRecall");
    }
    if(LM.getIssuer(loan) != msg.sender){
      revert("Invalid Recaller");
    }
    uint256 tokenId = LM.getTokenIdFromLoan(loan);
    recalls[tokenId] = block.timestamp;
  }
}