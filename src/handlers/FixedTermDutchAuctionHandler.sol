pragma solidity =0.8.17;

import {LoanManager, SpentItem, ReceivedItem, SettlementHandler} from "src/handlers/SettlementHandler.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";
import {FixedTermHook} from "src/hooks/FixedTermHook.sol";
import {DutchAuctionHandler} from "src/handlers/DutchAuctionHandler.sol";
import {StarPortLib} from "src/lib/StarPortLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract FixedTermDutchAuctionHandler is DutchAuctionHandler {
    using {StarPortLib.getId} for LoanManager.Loan;
    using FixedPointMathLib for uint256;

    constructor(LoanManager LM_) DutchAuctionHandler(LM_) {}

    function _getAuctionStart(LoanManager.Loan memory loan) internal view virtual override returns (uint256) {
        FixedTermHook.Details memory details = abi.decode(loan.terms.hookData, (FixedTermHook.Details));
        return loan.start + details.loanDuration;
    }

    function validate(LoanManager.Loan calldata loan) external view virtual override returns (bool) {
        return true;
    }
}
