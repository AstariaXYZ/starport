// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {DutchAuctionSettlement} from "starport-core/settlement/DutchAuctionSettlement.sol";
import {FixedTermStatus} from "starport-core/status/FixedTermStatus.sol";
import {Settlement} from "starport-core/settlement/Settlement.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

contract FixedTermDutchAuctionSettlement is DutchAuctionSettlement {
    using {StarportLib.getId} for Starport.Loan;
    using FixedPointMathLib for uint256;

    constructor(Starport SP_) DutchAuctionSettlement(SP_) {}

    // @inheritdoc DutchAuctionSettlement
    function getAuctionStart(Starport.Loan calldata loan) public view virtual override returns (uint256) {
        FixedTermStatus.Details memory details = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));
        return loan.start + details.loanDuration;
    }
}
