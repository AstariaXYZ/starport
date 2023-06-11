pragma solidity =0.8.17;

import {
  ItemType,
  ReceivedItem,
  SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {LoanManager} from "src/LoanManager.sol";
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
abstract contract Validator {
  error InvalidCaller();
  error InvalidDeadline();
  error InvalidValidator();
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

  struct Response {
    address lender;
    address conduit;
  }

  LoanManager public immutable LM;
  ConduitControllerInterface public immutable CI;
  ConduitInterface public immutable conduit;

  // Define the EIP712 domain and typehash constants for generating signatures
  bytes32 constant EIP_DOMAIN =
    keccak256(
      "EIP712Domain(string version,uint256 chainId,address verifyingContract)"
    );
  bytes32 public constant VALIDATOR_TYPEHASH =
    keccak256("ValidatorDetails(uint256 nonce,bytes32 hash)");
  bytes32 constant VERSION = keccak256("0");

  // Strategist address and fee
  address public strategist;
  uint256 public strategistFee;

  // Nonce mapping for replay protection
  mapping(address => uint256) private _counter;

  constructor(
    LoanManager LM_,
    ConduitControllerInterface CI_,
    address strategist_,
    uint256 fee_
  ) {
    strategist = strategist_;
    strategistFee = fee_;
    LM = LM_;
    CI = CI_;

    bytes32 conduitKey = bytes32(uint256(uint160(address(this))) << 96);
    conduit = ConduitInterface(CI.createConduit(conduitKey, address(this)));
    CI.updateChannel(address(conduit), address(LM), true);
  }

  // Abstract function to execute the loan, to be overridden in child contracts
  function validate(
    LoanManager.Loan calldata,
    bytes calldata,
    Signature calldata
  ) external view virtual returns (Response memory);

  // Encode the data with the account's nonce for generating a signature
  function encodeWithAccountCounter(
    address account,
    bytes calldata context
  ) public view virtual returns (bytes memory) {
    bytes32 hash = keccak256(
      abi.encode(VALIDATOR_TYPEHASH, _counter[account], keccak256(context))
    );
    return
      abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator(), hash);
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
}
