pragma solidity =0.8.17;

import {
  ItemType,
  ReceivedItem,
  SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {LoanManager} from "src/LoanManager.sol";

// Validator abstract contract that lays out the necessary structure and functions for the validator
abstract contract Validator {
  // Signature structure which consists of v, r, and s for ECDSA
  struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  // Define the EIP712 domain and typehash constants for generating signatures
  bytes32 constant EIP_DOMAIN = keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
  bytes32 public constant VALIDATOR_TYPEHASH = keccak256("ValidatorDetails(uint256 nonce,bytes32 hash)");
  bytes32 constant VERSION = keccak256("0");

  // Strategist address and fee
  address public strategist;
  uint256 public strategistFee;

  // Nonce mapping for replay protection
  mapping(address => uint256) private _counter;

  // Constructor function to initialize the strategist and strategist fee
  constructor(address strategist_, uint256 fee_) {
    strategist = strategist_;
    strategistFee = fee_;
  }

  // Abstract function to execute the loan, to be overridden in child contracts
  function execute(
    LoanManager.Loan calldata,
    Signature calldata,
    ReceivedItem calldata
  ) external virtual returns (address lender);

  // Abstract function to get owed amount, to be overridden in child contracts
  function getOwed(
    LoanManager.Loan calldata loan,
    uint256 timestamp
  ) external pure virtual returns (uint256);

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

  // Get the nonce of an account
  function getCounter(address account) public view virtual returns (uint256) {
    return _counter[account];
  }

  // Abstract function to get consideration when the loan is closed
  function getClosedConsideration(
    LoanManager.Loan calldata loan,
    SpentItem calldata maximumSpent
  ) external view virtual returns (ReceivedItem[] memory consideration);

  // Abstract function to check if the loan is healthy
  function isLoanHealthy(
    LoanManager.Loan calldata loan
  ) external view virtual returns (bool);

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
}
