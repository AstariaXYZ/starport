pragma solidity ^0.8.17;

import {LoanManager, SpentItem, ReceivedItem, SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";
import {BaseHook} from "starport-core/hooks/BaseHook.sol";
import {FixedTermHook} from "starport-core/hooks/FixedTermHook.sol";
import {DutchAuctionHandler} from "starport-core/handlers/DutchAuctionHandler.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract FixedTermDutchAuctionHandler is DutchAuctionHandler {
    using {StarPortLib.getId} for LoanManager.Loan;
    using FixedPointMathLib for uint256;

    constructor(LoanManager LM_) DutchAuctionHandler(LM_) {}

    function getAuctionStart(LoanManager.Loan calldata loan) public view virtual override returns (uint256) {
        FixedTermHook.Details memory details = abi.decode(loan.terms.hookData, (FixedTermHook.Details));
        return loan.start + details.loanDuration;
    }

    function execute(LoanManager.Loan calldata loan, address fulfiller) external virtual override returns (bytes4) {
        return SettlementHandler.execute.selector;
    }

    function validate(LoanManager.Loan calldata loan) external view virtual override returns (bool) {
        return true;
    }
}
