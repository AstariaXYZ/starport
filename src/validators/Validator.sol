pragma solidity =0.8.17;

import {
ItemType,
ReceivedItem, SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {LoanManager} from "src/LoanManager.sol";

abstract contract Validator {
    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
    bytes32 constant EIP_DOMAIN =
    keccak256(
        "EIP712Domain(string version,uint256 chainId,address verifyingContract)"
    );

    bytes32 public constant VALIDATOR_TYPEHASH =
    keccak256("ValidatorDetails(uint256 nonce,bytes32 hash)");

    bytes32 constant VERSION = keccak256("0");

    address public strategist;
    uint256 public strategistFee;

    mapping (address => uint256) private _counter;
    constructor(address strategist_, uint256 fee_) {
    strategist = strategist_;
      strategistFee = fee_;
    }

    function execute(
        LoanManager.Loan calldata,
        Signature calldata,
        ReceivedItem calldata
    ) external virtual returns (address lender);

    function getOwed(
        LoanManager.Loan calldata loan,
        uint256 timestamp
    ) external pure virtual returns (uint256);

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

    function getCounter(address account) public view virtual returns (uint256) {
        return _counter[account];
    }

    function getClosedConsideration(
        LoanManager.Loan calldata loan,
        SpentItem calldata maximumSpent
    ) external view virtual returns (ReceivedItem[] memory consideration);

    function isLoanHealthy(
        LoanManager.Loan calldata loan
    ) external view virtual returns (bool);

    function incrementCounter() external {
        _counter[msg.sender]++;
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
}
