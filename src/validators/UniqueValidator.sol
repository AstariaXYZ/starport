pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";
import {Validator} from "src/interfaces/Validator.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {
  ConduitTransfer,
  ConduitItemType
} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {
  ConduitInterface
} from "seaport-types/src/interfaces/ConduitInterface.sol";

contract UniqueValidator is Validator, AmountDeriver {
  bytes32 constant EIP_DOMAIN =
    keccak256(
      "EIP712Domain(string version,uint256 chainId,address verifyingContract)"
    );

  bytes32 public constant VALIDATOR_TYPEHASH =
    keccak256("ValidatorDetails(uint256 nonce,bytes32 root)");

  bytes32 constant VERSION = keccak256("0");

  struct Details {
    address validator;
    uint256 deadline;
    address conduit;
    address collateral;
    uint256 identifier;
    address debtToken;
    uint256 maxAmount;
    uint256 rate; //rate per second
    uint256 duration;
    bytes extraData;
  }

  LoanManager public immutable LM;

  constructor(LoanManager LM_) {
    LM = LM_;
  }

  function execute(
    LoanManager.NewLoanRequest calldata nlr,
    ReceivedItem calldata consideration
  ) external override returns (Loan memory, address lender) {
    Details memory details = abi.decode(nlr.details, (Details));

    if (address(this) != details.validator) {
      revert InvalidValidator();
    }
    if (block.timestamp > details.deadline) {
      revert InvalidDeadline();
    }
    if (
      details.collateral != consideration.token ||
      details.identifier != consideration.identifier
    ) {
      revert InvalidCollateral();
    }

    if (
      nlr.borrowerDetails.howMuch > details.maxAmount ||
      nlr.borrowerDetails.howMuch == 0
    ) {
      revert InvalidBorrowAmount();
    }

    if (nlr.borrowerDetails.what != details.debtToken) {
      revert InvalidDebtToken();
    }

    if (details.rate == 0) {
      revert InvalidRate();
    }

    lender = ecrecover(
      keccak256(encodeValidatorHash(lender, nlr.details)),
      nlr.v,
      nlr.r,
      nlr.s
    );

    ConduitTransfer[] memory transfers = new ConduitTransfer[](1);
    transfers[0] = ConduitTransfer(
      ConduitItemType.ERC20,
      nlr.borrowerDetails.what,
      lender,
      nlr.borrowerDetails.who,
      0,
      nlr.borrowerDetails.howMuch
    );
    ConduitInterface(details.conduit).execute(transfers);
    return (
      Loan({
        itemType: consideration.itemType,
        borrower: nlr.borrowerDetails.who,
        validator: address(this),
        token: consideration.token,
        identifier: consideration.identifier,
        identifierAmount: consideration.amount,
        debtToken: nlr.borrowerDetails.what,
        amount: nlr.borrowerDetails.howMuch,
        rate: details.rate,
        start: block.timestamp,
        duration: details.duration,
        nonce: uint256(0),
        extraData: details.extraData
      }),
      lender
    );
  }

  function getOwed(
    Loan calldata loan,
    uint256 timestamp
  ) public pure override returns (uint256) {
    return loan.amount * loan.rate * (loan.start + loan.duration - timestamp);
  }

  function getSettlementData(
    Loan calldata loan
  ) public view override returns (uint256, uint256) {
    (uint256 startPrice, uint256 endPrice, uint256 auctionDuration) = abi
      .decode(loan.extraData, (uint256, uint256, uint256));
    return (
      getOwed(loan, block.timestamp),
      _locateCurrentAmount({
        startAmount: startPrice,
        endAmount: endPrice,
        startTime: loan.start + loan.duration,
        endTime: block.timestamp + auctionDuration,
        roundUp: true
      })
    );
  }

  function encodeValidatorHash(
    address lender,
    bytes calldata context
  ) public view virtual returns (bytes memory) {
    bytes32 hash = keccak256(
      abi.encode(
        VALIDATOR_TYPEHASH,
        LM.seaport().getCounter(lender),
        keccak256(context)
      )
    );
    return
      abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator(), hash);
  }

  function domainSeparator() public view virtual returns (bytes32) {
    return
      keccak256(
        abi.encode(
          EIP_DOMAIN,
          VERSION, //version
          block.chainid,
          address(this)
        )
      );
  }

  error InvalidDeadline();
  error InvalidValidator();
  error InvalidCollateral();
  error InvalidBorrowAmount();
  error InvalidAmount();
  error InvalidDebtToken();
  error InvalidRate();
  error LoanHealthy();
}
