pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {BaseRecall} from "src/hooks/BaseRecall.sol";

contract AstariaV1SettlementHook is SettlementHook, BaseRecall {

    function isActive(LoanManager.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        uint256 tokenId = LM.getTokenIdFromLoan(loan);
        return !(recalls[tokenId] + details.recallWindow > block.timestamp);
    }
    function isRecalled(LoanManager.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        uint256 tokenId = LM.getTokenIdFromLoan(loan);
        return block.timestamp - details.recallWindow < recalls[tokenId];
    }
}
