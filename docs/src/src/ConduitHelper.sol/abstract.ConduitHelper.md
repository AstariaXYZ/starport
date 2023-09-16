# ConduitHelper
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/ConduitHelper.sol)


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

