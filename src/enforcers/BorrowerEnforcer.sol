// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";

import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";

contract BorrowerEnforcer is CaveatEnforcer {
    error BorrowerOnlyEnforcer();
    error InvalidLoanTerms();
    error InvalidAdditionalTransfer();

    struct Details {
        Starport.Loan loan;
    }

    /**
     * @dev Enforces that the loan terms are identical except for the issuer
     * The issuer is allowed to be any address
     * No additional transfers are permitted
     * @param additionalTransfers The additional transfers to be made
     * @param loan The loan terms
     * @param caveatData The borrowers encoded details
     */
    function validate(
        AdditionalTransfer[] calldata additionalTransfers,
        Starport.Loan calldata loan,
        bytes calldata caveatData
    ) public view virtual override {
        _validate(additionalTransfers, loan, abi.decode(caveatData, (Details)));
    }

    function _validate(
        AdditionalTransfer[] calldata additionalTransfers,
        Starport.Loan calldata loan,
        Details memory details
    ) internal pure {
        details.loan.issuer = loan.issuer;

        if (keccak256(abi.encode(loan)) != keccak256(abi.encode(details.loan))) revert InvalidLoanTerms();

        if (additionalTransfers.length > 0) {
            uint256 i = 0;
            for (; i < additionalTransfers.length;) {
                if (additionalTransfers[i].from == loan.borrower) revert InvalidAdditionalTransfer();
                unchecked {
                    ++i;
                }
            }
        }
    }
}
