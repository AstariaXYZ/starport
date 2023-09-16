# ConduitHelper
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/ConduitHelper.sol)


## Functions
### _mergeConsiderations


```solidity
function _mergeConsiderations(
    ReceivedItem[] memory repayConsideration,
    ReceivedItem[] memory carryConsideration,
    ReceivedItem[] memory additionalConsiderations
) internal returns (ReceivedItem[] memory consideration);
```

### _removeZeroAmounts


```solidity
function _removeZeroAmounts(ReceivedItem[] memory consideration)
    internal
    view
    returns (ReceivedItem[] memory newConsideration);
```

### _packageTransfers


```solidity
function _packageTransfers(ReceivedItem[] memory refinanceConsideration, address refinancer)
    internal
    pure
    returns (ConduitTransfer[] memory transfers);
```

## Errors
### RepayCarryLengthMismatch

```solidity
error RepayCarryLengthMismatch();
```

