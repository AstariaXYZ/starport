pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import {SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract SettlementHandler {
    function execute(LoanManager.Loan calldata loan) external virtual returns (bytes4) {
        return SettlementHandler.execute.selector;
    }

    function getSettlement(
        LoanManager.Loan memory loan,
        SpentItem[] calldata maximumSpent,
        uint256 owing,
        address payable lmOwner
    ) external view virtual returns (ReceivedItem[] memory consideration, address restricted);
}
