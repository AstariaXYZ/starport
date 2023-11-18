// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";
import {Validation} from "starport-core/lib/Validation.sol";

import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract Pricing is Validation {
    Starport public immutable SP;

    error InvalidRefinance();

    constructor(Starport SP_) {
        SP = SP_;
    }

    /**
     * @dev computes the payment details for a loan
     * @param loan      The loan to compute the payment details for
     */
    function getPaymentConsideration(Starport.Loan calldata loan)
        public
        view
        virtual
        returns (SpentItem[] memory, SpentItem[] memory);

    /**
     * @dev computes the refinance details for a loan
     * @param loan      The loan to compute the payment details for
     * @param newPricingData        The new pricing data being offered
     * @param fulfiller             The address of the fulfiller
     */
    function getRefinanceConsideration(Starport.Loan calldata loan, bytes calldata newPricingData, address fulfiller)
        external
        view
        virtual
        returns (SpentItem[] memory, SpentItem[] memory, AdditionalTransfer[] memory);
}
