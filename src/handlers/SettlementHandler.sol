pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import {SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract SettlementHandler {
    LoanManager LM;

    constructor(LoanManager LM_) {
        LM = LM_;
    }

    function execute(LoanManager.Loan calldata loan) external virtual returns (bytes4) {
        return SettlementHandler.execute.selector;
    }

    function validate(LoanManager.Loan calldata loan) external view virtual returns (bool);

    function getSettlement(LoanManager.Loan memory loan)
        external
        view
        virtual
        returns (ReceivedItem[] memory consideration, address restricted);
}
