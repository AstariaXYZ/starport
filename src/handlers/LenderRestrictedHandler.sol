pragma solidity =0.8.17;

import {LoanManager, SpentItem, ReceivedItem, SettlementHandler} from "src/handlers/SettlementHandler.sol";

contract LenderRestrictedHandler is SettlementHandler {
    constructor(LoanManager LM_) SettlementHandler(LM_) {}

    function getSettlement(LoanManager.Loan memory loan, SpentItem[] calldata maximumSpent)
        external
        view
        virtual
        override
        returns (ReceivedItem[] memory, address restricted)
    {
        return (new ReceivedItem[](0), LM.ownerOf(uint256(keccak256(abi.encode(loan)))));
    }

    function validate(LoanManager.Loan calldata loan) external view override returns (bool) {
        return true;
    }
}
