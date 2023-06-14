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

// Validator abstract contract that lays out the necessary structure and functions for the validator
abstract contract Originator {
  struct Response {
    LoanManager.Loan loan;
    address issuer;
  }
  error InvalidCaller();
  error InvalidDeadline();
  error InvalidOriginator();
  error InvalidCollateral();
  error InvalidBorrowAmount();
  error InvalidAmount();
  error InvalidDebtToken();
  error InvalidRate();
  error InvalidSigner();
  // Signature structure which consists of v, r, and s for ECDSA

  struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  LoanManager public immutable LM;

  struct ExecuteParams {
    //    LoanManager.Loan loan;
    //    uint256 loanId;
    address borrower;
    SpentItem[] collateral;
    SpentItem[] debt;
    bytes nlrDetails;
    Signature signature;
  }

  // Define the EIP712 domain and typehash constants for generating signatures
  bytes32 constant EIP_DOMAIN =
    keccak256(
      "EIP712Domain(string version,uint256 chainId,address verifyingContract)"
    );
  bytes32 public constant ORIGINATOR_DETAILS_TYPEHASH =
    keccak256(
      "OriginatorDetails(uint256 originator,uint256 nonce,bytes32 hash)"
    );
  bytes32 constant VERSION = keccak256("0");

  bytes32 internal immutable _DOMAIN_SEPARATOR;

  // Strategist address and fee
  address public strategist;
  uint256 public strategistFee;

  // Nonce mapping for replay protection
  mapping(address => uint256) private _counter;

  constructor(LoanManager LM_, address strategist_, uint256 fee_) {
    strategist = strategist_;
    strategistFee = fee_;
    LM = LM_;

    _DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        EIP_DOMAIN,
        VERSION, //version
        block.chainid,
        address(this)
      )
    );
  }

  function _packageTransfers(
    LoanManager.Loan memory loan,
    address issuer
  ) internal view returns (ConduitTransfer[] memory transfers) {
    uint256 i = 0;
    transfers = new ConduitTransfer[](loan.debt.length);
    for (; i < loan.debt.length; ) {
      ConduitItemType itemType;
      SpentItem memory debt = loan.debt[i];

      //forge-fmt skip-next-line
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
        token: loan.debt[i].token,
        identifier: loan.debt[i].identifier,
        amount: loan.debt[i].amount,
        to: loan.borrower
      });
      unchecked {
        ++i;
      }
    }
  }

  // Abstract function to execute the loan, to be overridden in child contracts
  function execute(
    ExecuteParams calldata
  ) external virtual returns (Response memory);

  // Encode the data with the account's nonce for generating a signature
  function encodeWithAccountCounter(
    address account,
    bytes32 contextHash
  ) public view virtual returns (bytes memory) {
    bytes32 hash = keccak256(
      abi.encode(
        ORIGINATOR_DETAILS_TYPEHASH,
        address(this),
        _counter[account],
        contextHash
      )
    );

    return
      abi.encodePacked(bytes1(0x19), bytes1(0x01), _DOMAIN_SEPARATOR, hash);
  }

  function getStrategistData() public view virtual returns (address, uint256) {
    return (strategist, strategistFee);
  }

  // Get the nonce of an account
  function getCounter(address account) public view virtual returns (uint256) {
    return _counter[account];
  }

  // Function to increment the nonce of the sender
  function incrementCounter() external {
    _counter[msg.sender]++;
  }

  // Function to generate the domain separator for signatures
  function domainSeparator() public view virtual returns (bytes32) {
    return _DOMAIN_SEPARATOR;
  }

  function _validateSignature(
    bytes32 hash,
    Signature memory signature
  ) internal view virtual {
    if (
      ECDSA.recover(hash, signature.v, signature.r, signature.s) != strategist
    ) {
      revert InvalidSigner();
    }
  }

  function getFeeConsideration(
    LoanManager.Loan calldata loan
  ) external view virtual returns (ReceivedItem memory consideration);
}
