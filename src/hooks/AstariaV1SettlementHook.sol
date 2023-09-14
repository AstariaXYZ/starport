pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {BaseRecall} from "src/hooks/BaseRecall.sol";
import "forge-std/console2.sol";

contract AstariaV1SettlementHook is SettlementHook, BaseRecall {
    
    constructor(LoanManager LM_) BaseRecall(LM_) {}
    function isActive(LoanManager.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        uint256 tokenId = LM.getLoanIdFromLoan(loan);
        return !(uint256(recalls[tokenId].start) + details.recallWindow > block.timestamp);
    }
    function isRecalled(LoanManager.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        uint256 tokenId = LM.getLoanIdFromLoan(loan);
        Recall memory recall = recalls[tokenId];
        return (recall.start + details.recallWindow > block.timestamp) && recall.start != 0;
    }
}
