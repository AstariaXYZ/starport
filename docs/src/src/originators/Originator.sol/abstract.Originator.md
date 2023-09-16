# Originator
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/originators/Originator.sol)


## State Variables
### LM

```solidity
LoanManager public immutable LM;
```


### EIP_DOMAIN

```solidity
bytes32 constant EIP_DOMAIN = keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
```


### ORIGINATOR_DETAILS_TYPEHASH

```solidity
bytes32 public constant ORIGINATOR_DETAILS_TYPEHASH =
    keccak256("OriginatorDetails(address originator,uint256 nonce,bytes32 hash)");
```


### VERSION

```solidity
bytes32 constant VERSION = keccak256("0");
```


### _DOMAIN_SEPARATOR

```solidity
bytes32 internal immutable _DOMAIN_SEPARATOR;
```


### strategist

```solidity
address public strategist;
```


### strategistFee

```solidity
uint256 public strategistFee;
```


### _counter

```solidity
uint256 private _counter;
```


## Functions
### constructor


```solidity
constructor(LoanManager LM_, address strategist_, uint256 fee_);
```

### _packageTransfers


```solidity
function _packageTransfers(SpentItem[] memory loan, address borrower, address issuer)
    internal
    pure
    returns (ConduitTransfer[] memory transfers);
```

### terms


```solidity
function terms(bytes calldata) external view virtual returns (LoanManager.Terms memory);
```

### execute


```solidity
function execute(Request calldata) external virtual returns (Response memory);
```

### encodeWithAccountCounter


```solidity
function encodeWithAccountCounter(address account, bytes32 contextHash) public view virtual returns (bytes memory);
```

### getStrategistData


```solidity
function getStrategistData() public view virtual returns (address, uint256);
```

### getCounter


```solidity
function getCounter() public view virtual returns (uint256);
```

### incrementCounter


```solidity
function incrementCounter() external;
```

### domainSeparator


```solidity
function domainSeparator() public view virtual returns (bytes32);
```

### _validateSignature


```solidity
function _validateSignature(bytes32 hash, bytes calldata signature) internal view virtual;
```

### getFeeConsideration


```solidity
function getFeeConsideration(LoanManager.Loan calldata loan)
    external
    view
    virtual
    returns (ReceivedItem[] memory consideration);
```

## Events
### Origination

```solidity
event Origination(uint256 indexed loanId, address indexed issuer, bytes nlrDetails);
```

### CounterUpdated

```solidity
event CounterUpdated();
```

## Errors
### InvalidCaller

```solidity
error InvalidCaller();
```

### InvalidCustodian

```solidity
error InvalidCustodian();
```

### InvalidDeadline

```solidity
error InvalidDeadline();
```

### InvalidOriginator

```solidity
error InvalidOriginator();
```

### InvalidCollateral

```solidity
error InvalidCollateral();
```

### InvalidBorrowAmount

```solidity
error InvalidBorrowAmount();
```

### InvalidAmount

```solidity
error InvalidAmount();
```

### InvalidDebtToken

```solidity
error InvalidDebtToken();
```

### InvalidRate

```solidity
error InvalidRate();
```

### InvalidSigner

```solidity
error InvalidSigner();
```

### InvalidLoan

```solidity
error InvalidLoan();
```

### InvalidTerms

```solidity
error InvalidTerms();
```

### InvalidDebtLength

```solidity
error InvalidDebtLength();
```

### InvalidDebtAmount

```solidity
error InvalidDebtAmount();
```

### ConduitTransferError

```solidity
error ConduitTransferError();
```

## Structs
### Response

```solidity
struct Response {
    LoanManager.Terms terms;
    address issuer;
}
```

### Request

```solidity
struct Request {
    address custodian;
    address receiver;
    SpentItem[] collateral;
    SpentItem[] debt;
    bytes details;
    bytes signature;
}
```

## Enums
### State

```solidity
enum State {
    INITIALIZED,
    CLOSED
}
```

