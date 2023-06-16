pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import "src/originators/Originator.sol";

contract UniqueOriginator is Originator {
    error InvalidLoan();
    error InvalidTerms();
    error InvalidDebtLength();
    error InvalidDebtAmount();
    error ConduitTransferError();

    constructor(LoanManager LM_, address strategist_, uint256 fee_) Originator(LM_, strategist_, fee_) {}

    struct Details {
        address conduit;
        address issuer;
        uint256 deadline;
        LoanManager.Terms terms;
        SpentItem[] collateral;
        SpentItem debt;
    }

    function build(Request calldata params) public view override returns (Response memory response) {
        Details memory details = abi.decode(params.details, (Details));
        response = _build(params, details);
    }

    function _build(Request calldata params, Details memory details) internal pure returns (Response memory response) {
        SpentItem[] memory debt = new SpentItem[](1);
        debt[0] = details.debt;
        response = Response({terms: details.terms, issuer: details.issuer});
    }

    function execute(Request calldata params) external override returns (Response memory response) {
        bytes32 contextHash = keccak256(params.details);

        _validateSignature(keccak256(encodeWithAccountCounter(strategist, contextHash)), params.signature);
        Details memory details = abi.decode(params.details, (Details));

        if (block.timestamp > details.deadline) {
            revert InvalidDeadline();
        }

        if (params.debt.length > 1) {
            revert InvalidDebtLength();
        }

        if (
            ConduitInterface(details.conduit).execute(_packageTransfers(params.debt, params.borrower, details.issuer))
                != ConduitInterface.execute.selector
        ) {
            revert ConduitTransferError();
        }

        response = _build(params, details);
    }

    event Origination(uint256 indexed loanId, address indexed issuer, bytes nlrDetails);

    enum State {
        INITIALIZED,
        CLOSED
    }

    function getFeeConsideration(LoanManager.Loan calldata loan)
        external
        view
        override
        returns (ReceivedItem memory consideration)
    {
        consideration;
    }
}
