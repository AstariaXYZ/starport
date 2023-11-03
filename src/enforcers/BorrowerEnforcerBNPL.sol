pragma solidity ^0.8.17;

import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";
import {Starport} from "starport-core/Starport.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";

contract BorrowerEnforcerBNPL is CaveatEnforcer {
    error BorrowerOnlyEnforcer();
    error InvalidLoanTerms();
    error InvalidAdditionalTransfer();

    error OrderInvalid();

    struct Details {
        Starport.Loan loan;
        address seaport;
        bytes32 offerHash;
        AdditionalTransfer additionalTransfer;
    }

    function validate(
        AdditionalTransfer[] calldata additionalTransfers,
        Starport.Loan calldata loan,
        bytes calldata caveatData
    ) public view virtual override {
        bytes32 loanHash = keccak256(abi.encode(loan));

        Details memory details = abi.decode(caveatData, (Details));
        if (details.loan.borrower != loan.borrower) {
            revert BorrowerOnlyEnforcer();
        }
        details.loan.issuer = loan.issuer;

        if (loanHash != keccak256(abi.encode(details.loan))) {
            revert InvalidLoanTerms();
        }

        if (additionalTransfers.length > 0) {
            if (details.offerHash != bytes32(0)) {
                (bool isValidated, bool isCancelled, uint256 numerator, uint256 denominator) =
                    ConsiderationInterface(details.seaport).getOrderStatus(details.offerHash);

                if (isCancelled || !isValidated) {
                    revert OrderInvalid();
                }

                if (additionalTransfers.length > 1) {
                    revert InvalidAdditionalTransfer();
                }
                if (
                    additionalTransfers[0].itemType != details.additionalTransfer.itemType
                        || additionalTransfers[0].identifier != details.additionalTransfer.identifier
                        || additionalTransfers[0].amount > details.additionalTransfer.amount
                        || additionalTransfers[0].token != details.additionalTransfer.token
                ) {
                    revert InvalidAdditionalTransfer();
                }
            } else {
                revert InvalidAdditionalTransfer();
            }
        }
    }
}
