//pragma solidity =0.8.17;
//import "src/originators/Originator.sol";
//
//import {LoanManager} from "src/LoanManager.sol";
//import {ERC4626} from "solady/src/tokens/ERC4626.sol";
//
//contract PoolOriginator is Originator {
//  error InvalidLoan();
//  error InvalidTerms();
//  error InvalidDebtLength();
//  error ConduitTransferError();
//
//  constructor(
//    LoanManager LM_,
//    address strategist_,
//    uint256 fee_
//  ) Originator(LM_, strategist_, fee_) {}
//
//  struct Details {
//    address conduit;
//    address issuer;
//    uint256 deadline;
//    LoanManager.Terms terms;
//    SpentItem[] collateral;
//    SpentItem debt;
//  }
//
//  function execute(
//    ExecuteParams calldata params
//  ) external override returns (address issuer) {
//    bytes32 contextHash = keccak256(params.nlrDetails);
//
//    _validateSignature(
//      keccak256(encodeWithAccountCounter(strategist, contextHash)),
//      params.signature
//    );
//    Details memory details = abi.decode(params.nlrDetails, (Details));
//    LoanManager.Loan calldata loan = params.loan;
//
//    if (block.timestamp > details.deadline) {
//      revert InvalidDeadline();
//    }
//
//    if (loan.debt.length > 1) {
//      revert InvalidDebtLength();
//    }
//
//    //    bool[] memory found = new bool[](loan.collateral.length);
//    //    uint256 matchCount = 0;
//    //    uint256 length = loan.collateral.length;
//    //    uint256 detailsLength = details.collateral.length;
//    //    uint i = 0;
//    //    uint j = 0;
//    //    for (; i < length; i++) {
//    //      if (matchCount == loan.collateral.length) {
//    //        break;
//    //      }
//    //      for (; j < detailsLength; j++) {
//    //        if (
//    //          !found[i] && matchCount != loan.collateral[i].length && details.collateral[j].identifier != 0 && loan.collateral[i].identifier != 0 &&
//    //        loan.collateral[i].itemType == details.collateral[j].itemType &&
//    //        loan.collateral[i].token == details.collateral[j].token &&
//    //        loan.collateral[i].identifier == details.collateral[j].identifier &&
//    //        loan.collateral[i].amount < details.collateral[j].amount &&
//    //
//    //        ) {
//    //          found[i] = true;
//    //          matchCount++;
//    //          if (matchCount == loan.collateral.length) {
//    //            break;
//    //          }
//    //        }
//    //      }
//    //    }
//    //    if (matchCount != loan.collateral.length) {
//    //      revert InvalidCollateral();
//    //    }
//    //
//    //    found = new bool[](loan.debt.length);
//    //    matchCount = 0;
//    //    length = loan.debt.length;
//    //    detailsLength = details.debt.length;
//    //    i = 0;
//    //    j = 0;
//    //    //    for (; i < length; i++) {
//    //    //      for (; j < detailsLength; j++) {
//    //    //        if (
//    //    //          loan.debt[i].itemType == details.debt[j].itemType &&
//    //    //          loan.debt[i].token == details.debt[j].token &&
//    //    //          loan.debt[i].identifier != 0 &&
//    //    //          loan.debt[i].identifier == details.debt[j].identifier &&
//    //    //          loan.debt[i].amount < details.debt[j].amount &&
//    //    //          !found[i]
//    //    //        ) {
//    //    //          found[i] = true;
//    //    //          matchCount++;
//    //    //        }
//    //    //        if (matchCount == loan.debt.length) {
//    //    //          break;
//    //    //        }
//    //    //      }
//    //    //    }
//    //
//    if (
//      //      keccak256(abi.encode(loan.collateral)) !=
//      //      keccak256(abi.encode(details.collateral)) ||
//      keccak256(abi.encode(loan.terms)) != keccak256(abi.encode(details.terms))
//    ) {
//      revert InvalidTerms();
//    }
//
//    if (
//      ConduitInterface.execute.selector !=
//      ConduitInterface(details.conduit).execute(
//        _packageTransfers(loan, details.issuer)
//      )
//    ) {
//      revert ConduitTransferError();
//    }
//    //    emit Origination(params.loanId, details.issuer, params.nlrDetails);
//    //the recipient is the issuer since we reuse the struct
//    //    LoanManager(msg.sender).mint(loan, details.issuer);
//    //    selector = Originator.execute.selector;
//    issuer = details.issuer;
//  }
//
//  event Origination(
//    uint256 indexed loanId,
//    address indexed issuer,
//    bytes nlrDetails
//  );
//
//  enum State {
//    INITIALIZED,
//    CLOSED
//  }
//
//  function getFeeConsideration(
//    LoanManager.Loan calldata loan
//  ) external view override returns (ReceivedItem memory consideration) {}
//}
