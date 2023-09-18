pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import {
  ItemType,
  ReceivedItem,
  SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {
  ConduitTransfer,
  ConduitItemType
} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {
  ConduitControllerInterface
} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {
  ConduitInterface
} from "seaport-types/src/interfaces/ConduitInterface.sol";

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";

// Validator abstract contract that lays out the necessary structure and functions for the validator
abstract contract Originator {
  error ConduitTransferError();

  enum State {
    INITIALIZED,
    CLOSED
  }
  struct Response {
    LoanManager.Terms terms;
    address issuer;
  }

  struct Request {
    address custodian;
    address receiver;
    SpentItem[] collateral;
    SpentItem[] debt;
    bytes details;
    bytes signature;
  }

  event Origination(
    uint256 indexed loanId,
    address indexed issuer,
    bytes nlrDetails
  );

  function _packageTransfers(
    SpentItem[] memory loan,
    address borrower,
    address issuer
  ) internal pure returns (ConduitTransfer[] memory transfers) {
    uint256 i = 0;
    transfers = new ConduitTransfer[](loan.length);
    for (; i < loan.length; ) {
      ConduitItemType itemType;
      SpentItem memory debt = loan[i];

      assembly {
        itemType := mload(debt)
        switch itemType
        case 1 {

        }
        case 2 {

        }
        case 3 {

        }
        default {
          revert(0, 0)
        } //TODO: Update with error selector - InvalidContext(ContextErrors.INVALID_LOAN)
      }
      transfers[i] = ConduitTransfer({
        itemType: itemType,
        from: issuer,
        token: loan[i].token,
        identifier: loan[i].identifier,
        amount: loan[i].amount,
        to: borrower
      });
      unchecked {
        ++i;
      }
    }
  }

  function terms(
    bytes calldata
  ) external view virtual returns (LoanManager.Terms memory);

  // Abstract function to execute the loan, to be overridden in child contracts
  function execute(Request calldata) external virtual returns (Response memory);


  function getFeeConsideration(
    LoanManager.Loan calldata loan
  ) external view virtual returns (ReceivedItem[] memory consideration);
}
