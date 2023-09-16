pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {BaseRecall} from "src/hooks/BaseRecall.sol";
import "forge-std/console2.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";
import {StarPortLib} from "src/lib/StarPortLib.sol";

contract AstariaV1SettlementHook is BaseHook, BaseRecall {
    using {StarPortLib.getId} for LoanManager.Loan;

    constructor(LoanManager LM_) BaseRecall(LM_) {}

    function isActive(LoanManager.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        uint256 tokenId = loan.getId();
        return !(uint256(recalls[tokenId].start) + details.recallWindow > block.timestamp);
    }

    function isRecalled(LoanManager.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        uint256 tokenId = loan.getId();
        Recall memory recall = recalls[tokenId];
        return (recall.start + details.recallWindow > block.timestamp) && recall.start != 0;
    }
}
