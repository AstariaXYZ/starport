pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import "src/originators/Originator.sol";

contract UniqueOriginator is Originator {
    error InvalidLoan();

    constructor(LoanManager LM_, ConduitControllerInterface CI_, address strategist_, uint256 fee_)
        Originator(LM_, CI_, strategist_, fee_)
    {}

    struct Details {
        address originator;
        address hook; // isLoanHealthy
        address pricing; // getOwed
        address handler; // liquidationMethod
        uint256 deadline;
        bytes pricingData;
        bytes handlerData;
        bytes hookData;
        SpentItem collateral;
        ReceivedItem debt;
    }

    function validate(LoanManager.Loan calldata loan, bytes calldata nlrDetails, Signature calldata signature)
        external
        view
        override
        returns (Response memory response)
    {
        if (msg.sender != address(LM)) {
            revert InvalidCaller();
        }

        Details memory details = abi.decode(nlrDetails, (Details));

        if (address(this) != details.originator) {
            revert InvalidOriginator();
        }

        if (block.timestamp > details.deadline) {
            revert InvalidDeadline();
        }

        if (
            details.debt.token != loan.debt.token || details.debt.identifier != loan.debt.identifier
                || details.debt.itemType != loan.debt.itemType || loan.debt.amount > details.debt.amount
                || loan.debt.amount == 0
        ) {
            revert InvalidDebtToken();
        }

        if (
            loan.hook != details.hook || loan.handler != details.handler || loan.pricing != details.pricing
                || keccak256(loan.pricingData) != keccak256(details.pricingData)
                || keccak256(loan.handlerData) != keccak256(details.handlerData)
                || keccak256(loan.hookData) != keccak256(details.hookData)
        ) {
            revert InvalidLoan();
        }

        _validateSignature(keccak256(encodeWithAccountCounter(strategist, nlrDetails)), signature);

        //the recipient is the lender since we reuse the struct
        return Response({lender: details.debt.recipient, conduit: address(conduit)});
    }
}
