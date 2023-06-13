pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import "src/originators/Originator.sol";

contract UniqueOriginator is Originator {
  error InvalidLoan();
  error InvalidDebtLength();
  error ConduitTransferError();

  constructor(
    LoanManager LM_,
    address strategist_,
    uint256 fee_
  ) Originator(LM_, strategist_, fee_) {}

  struct Details {
    address originator;
    address conduit;
    address lender;
    address hook; // isLoanHealthy
    address pricing; // getOwed
    address handler; // liquidationMethod
    uint256 deadline;
    bytes pricingData;
    bytes handlerData;
    bytes hookData;
    SpentItem[] collateral;
    SpentItem[] debt;
  }

  function execute(
    ExecuteParams calldata params
  ) external override returns (bytes4 selector) {
    Details memory details = abi.decode(params.nlrDetails, (Details));
    LoanManager.Loan calldata loan = params.loan;

    if (address(this) != details.originator) {
      revert InvalidOriginator();
    }

    if (block.timestamp > details.deadline) {
      revert InvalidDeadline();
    }

    if (loan.debt.length > details.debt.length) {
      revert InvalidDebtLength();
    }

    bool[] memory found = new bool[](loan.collateral.length);
    uint256 matchCount = 0;
    uint256 length = loan.collateral.length;
    uint256 detailsLength = details.collateral.length;
    uint i = 0;
    uint j = 0;
    for (; i < length; i++) {
      for (; j < detailsLength; j++) {
        if (
          loan.debt[i].itemType == details.collateral[j].itemType &&
          loan.debt[i].token == details.collateral[j].token &&
          loan.debt[i].identifier != 0 &&
          loan.debt[i].identifier == details.collateral[j].identifier &&
          loan.debt[i].amount < details.collateral[j].amount &&
          !found[i]
        ) {
          found[i] = true;
          matchCount++;
        }
        if (matchCount == loan.collateral.length) {
          break;
        }
      }
    }

    found = new bool[](loan.debt.length);
    matchCount = 0;
    length = loan.debt.length;
    detailsLength = details.debt.length;
    i = 0;
    j = 0;
    for (; i < length; i++) {
      for (; j < detailsLength; j++) {
        if (
          loan.debt[i].itemType == details.debt[j].itemType &&
          loan.debt[i].token == details.debt[j].token &&
          loan.debt[i].identifier != 0 &&
          loan.debt[i].identifier == details.debt[j].identifier &&
          loan.debt[i].amount < details.debt[j].amount &&
          !found[i]
        ) {
          found[i] = true;
          matchCount++;
        }
        if (matchCount == loan.debt.length) {
          break;
        }
      }
    }

    if (
      loan.hook != details.hook ||
      loan.handler != details.handler ||
      loan.pricing != details.pricing ||
      keccak256(loan.pricingData) != keccak256(details.pricingData) ||
      keccak256(loan.handlerData) != keccak256(details.handlerData) ||
      keccak256(loan.hookData) != keccak256(details.hookData)
    ) {
      revert InvalidLoan();
    }

    _validateSignature(
      keccak256(encodeWithAccountCounter(strategist, params.nlrDetails)),
      params.signature
    );
    //    bytes memory encodedLoan = abi.encode(loan);

    if (
      ConduitInterface.execute.selector !=
      ConduitInterface(details.conduit).execute(
        _packageTransfers(loan, details.lender)
      )
    ) {
      revert ConduitTransferError();
    }

    LoanManager(msg.sender).mint(
      details.lender,
      params.loanId,
      params.encodedLoan
    );

    //the recipient is the lender since we reuse the struct
    return Originator.execute.selector;
  }

  function getFeeConsideration(
    LoanManager.Loan calldata loan
  ) external view override returns (ReceivedItem memory consideration) {}
}
