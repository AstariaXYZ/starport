pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {
  ConduitTransfer,
  ConduitItemType
} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {
  ConduitInterface
} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {
  ConduitControllerInterface
} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./Validator.sol";
import "forge-std/console.sol";

contract UniqueValidator is Validator, AmountDeriver {
  using FixedPointMathLib for uint256;
  struct SettlementData {
    uint256 startingPrice;
    uint256 endingPrice;
    uint256 window;
  }
  struct Details {
    address validator;
    uint256 deadline;
    address conduit;
    address collateral;
    uint256 identifier;
    address debtToken;
    uint256 maxAmount;
    uint256 rate; //rate per second
    uint256 loanDuration;
    SettlementData settlement;
  }

  LoanManager public immutable LM;
  ConduitControllerInterface public immutable CI;

  constructor(
    LoanManager LM_,
    ConduitControllerInterface CI_,
    address strategist_,
    uint256 fee_
  ) Validator(strategist_, fee_) {
    LM = LM_;
    CI = CI_;
  }

  function execute(
    LoanManager.Loan calldata loan,
    Signature calldata signature,
    ReceivedItem calldata consideration
  ) external override returns (address recipient) {
    if (msg.sender != address(LM)) {
      revert InvalidCaller();
    }

    Details memory details = _decodeLoanDetails(loan);

    _validateExecution(details, consideration, loan, signature);

    recipient = _executeConduitTransfer(details, loan);
  }

  function _decodeLoanDetails(LoanManager.Loan calldata loan) internal view returns (Details memory details) {
    details = abi.decode(loan.details, (Details));

    if (address(this) != details.validator) {
      revert InvalidValidator();
    }
    if (block.timestamp > details.deadline) {
      revert InvalidDeadline();
    }

    return details;
  }

  function _validateExecution(
    Details memory details,
    ReceivedItem calldata consideration,
    LoanManager.Loan calldata loan,
    Signature calldata signature
  ) internal view {
    if (
      details.collateral != consideration.token ||
      details.identifier != consideration.identifier
    ) {
      revert InvalidCollateral();
    }
    if (details.rate == 0) {
      revert InvalidRate();
    }
    if (loan.debt.amount > details.maxAmount || loan.debt.amount == 0) {
      revert InvalidBorrowAmount();
    }

    if (loan.debt.token != details.debtToken) {
      revert InvalidDebtToken();
    }

    address signer = ecrecover(
      keccak256(encodeWithAccountCounter(strategist, loan.details)),
      signature.v,
      signature.r,
      signature.s
    );

    if (signer != strategist) {
      revert InvalidSigner(signer);
    }
  }

  function _executeConduitTransfer(Details memory details, LoanManager.Loan calldata loan) internal returns (address recipient) {
    recipient = CI.ownerOf(address(details.conduit));
    ConduitTransfer[] memory transfers = new ConduitTransfer[](1);
    transfers[0] = ConduitTransfer(
      ConduitItemType.ERC20,
      loan.debt.token,
      recipient,
      loan.debt.recipient,
      loan.debt.identifier,
      loan.debt.amount
    );
    if (
      ConduitInterface(details.conduit).execute(transfers) !=
      ConduitInterface.execute.selector
    ) {
      revert InvalidConduitTransfer();
    }

    return recipient;
  }

  function isLoanHealthy(
    LoanManager.Loan calldata loan
  ) external view override returns (bool) {
    Details memory details = abi.decode(loan.details, (Details));
    return loan.start + details.loanDuration < block.timestamp;
  }

  function getOwed(
    LoanManager.Loan calldata loan,
    uint256 timestamp
  ) public pure override returns (uint256) {
    Details memory details = abi.decode(loan.details, (Details));
    return _getOwed(loan, details, timestamp);
  }

  function _getOwed(
    LoanManager.Loan memory loan,
    Details memory details,
    uint256 timestamp
  ) internal pure returns (uint256) {
    return
      loan.debt.amount *
      details.rate *
      (loan.start + details.loanDuration - timestamp);
  }

  function getClosedConsideration(
    LoanManager.Loan memory loan,
    SpentItem calldata maximumSpent
  )
  external
  view
  virtual
  override
  returns (ReceivedItem[] memory consideration)
  {
    Details memory details = abi.decode(loan.details, (Details));
    uint256 settlementPrice;
    uint256 owing = _getOwed(loan, details, block.timestamp);
    if (loan.start + details.loanDuration < block.timestamp) {
      settlementPrice = owing;
    } else {
      settlementPrice = _locateCurrentAmount({
      startAmount: details.settlement.startingPrice,
      endAmount: details.settlement.endingPrice,
      startTime: loan.start + details.loanDuration,
      endTime: block.timestamp + details.settlement.window,
      roundUp: true
      });
    }

    if (maximumSpent.amount < settlementPrice) {
      revert InvalidAmount();
    }

    uint256 fee = settlementPrice.mulWadDown(strategistFee);
    uint256 considerationLength = 1;
    uint256 payment = maximumSpent.amount;
    if (fee > 0) {
      considerationLength = 2;
    }
    if (payment - fee > owing) {
      considerationLength = 3;
    }

    consideration = new ReceivedItem[](considerationLength);

    if (considerationLength > 1) {
      consideration[0] = ReceivedItem({
      itemType: ItemType.ERC20,
      token: loan.debt.token,
      identifier: 0,
      amount: fee,
      recipient: payable(strategist)
      });
    }

    //set the borrower slot and lender recipient after as we havent mutated the loan yet

    if (considerationLength == 3) {
      consideration[2] = ReceivedItem({
      itemType: ItemType.ERC20,
      token: loan.debt.token,
      identifier: loan.debt.identifier,
      amount: payment - fee - owing,
      recipient: payable(loan.debt.recipient) // currently borrower
      });
    }

    //override to lender
    loan.debt.recipient = payable(
      LM.ownerOf(uint256(keccak256(abi.encode(loan))))
    );
    loan.debt.amount = considerationLength == 3 ? owing : payment - fee;
    consideration[considerationLength == 1 ? 0 : 1] = loan.debt;
  }


  error InvalidCaller();
  error InvalidDeadline();
  error InvalidValidator();
  error InvalidCollateral();
  error InvalidBorrowAmount();
  error InvalidAmount();
  error InvalidDebtToken();
  error InvalidRate();
  error InvalidSigner(address);
  error InvalidConduitTransfer();
  error LoanHealthy();
}
