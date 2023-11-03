pragma solidity ^0.8.17;

import {Starport, SpentItem, ReceivedItem, Settlement} from "starport-core/settlement/Settlement.sol";
import {BaseStatus} from "starport-core/status/BaseStatus.sol";
import {FixedTermStatus} from "starport-core/status/FixedTermStatus.sol";
import {DutchAuctionSettlement} from "starport-core/settlement/DutchAuctionSettlement.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract FixedTermDutchAuctionSettlement is DutchAuctionSettlement {
    using {StarportLib.getId} for Starport.Loan;
    using FixedPointMathLib for uint256;

    constructor(Starport SP_) DutchAuctionSettlement(SP_) {}

    function getAuctionStart(Starport.Loan calldata loan) public view virtual override returns (uint256) {
        FixedTermStatus.Details memory details = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));
        return loan.start + details.loanDuration;
    }

    function execute(Starport.Loan calldata loan, address fulfiller) external virtual override returns (bytes4) {
        return Settlement.execute.selector;
    }

    function validate(Starport.Loan calldata loan) external view virtual override returns (bool) {
        return true;
    }
}
