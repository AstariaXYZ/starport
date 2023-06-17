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
        address custodian;
        address conduit;
        address issuer;
        uint256 deadline;
        LoanManager.Terms terms;
        SpentItem[] collateral;
        SpentItem[] debt;
    }

    function terms(bytes calldata details) public view override returns (LoanManager.Terms memory) {
        return abi.decode(details, (Details)).terms;
    }

    function _build(Request calldata params, Details memory details) internal view returns (Response memory response) {
        bool needsMint = details.issuer.code.length > 0;
        response = Response({terms: details.terms, mint: needsMint, issuer: details.issuer});
    }

    function execute(Request calldata params) external override returns (Response memory response) {
        bytes32 contextHash = keccak256(params.details);

        _validateSignature(keccak256(encodeWithAccountCounter(strategist, contextHash)), params.signature);
        Details memory details = abi.decode(params.details, (Details));

        if (block.timestamp > details.deadline) {
            revert InvalidDeadline();
        }

        _validateAsk(params, details);
        if (params.debt.length > 1) {
            revert InvalidDebtLength();
        }

        if (
            ConduitInterface(details.conduit).execute(_packageTransfers(params.debt, params.receiver, details.issuer))
                != ConduitInterface.execute.selector
        ) {
            revert ConduitTransferError();
        }

        response = _build(params, details);
    }

    function _validateAsk(Request calldata request, Details memory details) internal {
        //    if (request.borrower == address(0)) {
        //      revert InvalidBorrower();
        //    }
        //    if (request.custodian != details.custodian) {
        //      revert InvalidCustodian();
        //    }
        //    if (request.details.length > 0) {
        //      revert InvalidDetails();
        //    }
        //    if (keccak256(request.collateral))
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
