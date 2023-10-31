pragma solidity ^0.8.17;

import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {ConduitTransfer} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {LoanManager} from "starport-core/LoanManager.sol";

contract LenderEnforcer is CaveatEnforcer {
    error LenderOnlyEnforcer();
    error InvalidLoanTerms();
    error InvalidAdditionalTransfer();

    struct Details {
        LoanManager.Loan loan;
    }

    function validate(
        ConduitTransfer[] calldata additionalTransfers,
        LoanManager.Loan calldata loan,
        bytes calldata caveatData
    ) public view virtual override {
        Details memory details = abi.decode(caveatData, (Details));
        if (details.loan.issuer != loan.issuer) revert LenderOnlyEnforcer();
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
