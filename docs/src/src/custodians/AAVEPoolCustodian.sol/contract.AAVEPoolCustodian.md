# AAVEPoolCustodian
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/custodians/AAVEPoolCustodian.sol)

**Inherits:**
[Custodian](/src/Custodian.sol/contract.Custodian.md)


## State Variables
### pool

```solidity
IPool public pool;
```


## Functions
### constructor


```solidity
constructor(LoanManager LM_, address seaport_, address pool_) Custodian(LM_, seaport_);
```

### custody


```solidity
function custody(
    ReceivedItem[] calldata consideration,
    bytes32[] calldata orderHashes,
    uint256 contractNonce,
    bytes calldata context
) external override returns (bytes4 selector);
```

### _beforeApprovalsSetHook


```solidity
function _beforeApprovalsSetHook(address fulfiller, SpentItem[] calldata maximumSpent, bytes calldata context)
    internal
    virtual
    override;
```

### _enter


```solidity
function _enter(address token, uint256 amount) internal;
```

### _exit


```solidity
function _exit(address token, uint256 amount) internal;
```

