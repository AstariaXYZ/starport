# BaseRecall
[Git Source](https://github.com/AstariaXYZ/starport/blob/579f2b696f3db97ba152a0f0d28350598ebf1089/src/hooks/BaseRecall.sol)

**Inherits:**
[ConduitHelper](/src/ConduitHelper.sol/abstract.ConduitHelper.md)


## State Variables
### LM

```solidity
LoanManager LM;
```


### seaport

```solidity
ConsiderationInterface public constant seaport = ConsiderationInterface(0x2e234DAe75C793f67A35089C9d99245E1C58470b);
```


### recalls

```solidity
mapping(uint256 => Recall) public recalls;
```


## Functions
### constructor


```solidity
constructor(LoanManager LM_);
```

### getRecallRate


```solidity
function getRecallRate(LoanManager.Loan calldata loan) external view returns (uint256);
```

### recall


```solidity
function recall(LoanManager.Loan memory loan, address conduit) external;
```

### withdraw


```solidity
function withdraw(LoanManager.Loan memory loan, address payable receiver) external;
```

### _getRecallStake


```solidity
function _getRecallStake(LoanManager.Loan memory loan, uint256 start, uint256 end)
    internal
    view
    returns (uint256[] memory recallStake);
```

### generateRecallConsideration


```solidity
function generateRecallConsideration(LoanManager.Loan memory loan, uint256 proportion, address payable receiver)
    external
    view
    returns (ReceivedItem[] memory consideration);
```

### _generateRecallConsideration


```solidity
function _generateRecallConsideration(
    LoanManager.Loan memory loan,
    uint256 start,
    uint256 end,
    uint256 proportion,
    address payable receiver
) internal view returns (ReceivedItem[] memory consideration);
```

## Events
### Recalled

```solidity
event Recalled(uint256 loandId, address recaller, uint256 end);
```

### Withdraw

```solidity
event Withdraw(uint256 loanId, address withdrawer);
```

## Errors
### InvalidWithdraw

```solidity
error InvalidWithdraw();
```

### InvalidConduit

```solidity
error InvalidConduit();
```

### ConduitTransferError

```solidity
error ConduitTransferError();
```

### InvalidStakeType

```solidity
error InvalidStakeType();
```

### LoanDoesNotExist

```solidity
error LoanDoesNotExist();
```

### RecallBeforeHoneymoonExpiry

```solidity
error RecallBeforeHoneymoonExpiry();
```

### LoanHasNotBeenRefinanced

```solidity
error LoanHasNotBeenRefinanced();
```

### WithdrawDoesNotExist

```solidity
error WithdrawDoesNotExist();
```

## Structs
### Details

```solidity
struct Details {
    uint256 honeymoon;
    uint256 recallWindow;
    uint256 recallStakeDuration;
    uint256 recallMax;
}
```

### Recall

```solidity
struct Recall {
    address payable recaller;
    uint64 start;
}
```

