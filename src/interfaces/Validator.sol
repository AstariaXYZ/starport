pragma solidity =0.8.17;

import {
  ItemType,
  ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {LoanManager} from "src/LoanManager.sol";

interface Validator {
  struct Loan {
    ItemType itemType;
    address borrower;
    address validator;
    address token;
    address debtToken;
    uint256 identifier;
    uint256 identifierAmount;
    uint256 amount;
    uint256 rate;
    uint256 start;
    uint256 duration;
    uint256 nonce;
    bytes extraData;
  }

  function execute(
    LoanManager.NewLoanRequest calldata nlr,
    ReceivedItem calldata consideration
  ) external returns (Loan memory, address lender);

  function getOwed(
    Loan calldata loan,
    uint256 timestamp
  ) external pure returns (uint256);

  function getSettlementData(
    Loan calldata loan
  ) external view returns (uint256, uint256);
}
