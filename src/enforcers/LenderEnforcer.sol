pragma solidity ^0.8.17;

import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";
import {Starport} from "starport-core/Starport.sol";

contract LenderEnforcer is CaveatEnforcer {
    error LenderOnlyEnforcer();
    error InvalidLoanTerms();
    error InvalidAdditionalTransfer();

    struct Details {
        Starport.Loan loan;
    }

    /// @notice Enforces that the loan terms are identical except for the borrower
    /// @notice The borrower is allowed to be any address
    /// @notice No additional transfers from the issuer are permitted
    /// @param additionalTransfers The additional transfers to be made
    /// @param loan The loan terms
    /// @param caveatData The borrowers encoded details
    function validate(
        AdditionalTransfer[] calldata additionalTransfers,
        Starport.Loan calldata loan,
        bytes calldata caveatData
    ) public view virtual override {
        Details memory details = abi.decode(caveatData, (Details));
        details.loan.borrower = loan.borrower;

        if (keccak256(abi.encode(loan)) != keccak256(abi.encode(details.loan))) {
            revert InvalidLoanTerms();
        }

        if (additionalTransfers.length > 0) {
            uint256 i = 0;
            for (; i < additionalTransfers.length;) {
                if (additionalTransfers[i].from == loan.issuer) revert InvalidAdditionalTransfer();
                unchecked {
                    ++i;
                }
            }
        }
    }
}
