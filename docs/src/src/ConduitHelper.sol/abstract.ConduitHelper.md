# ConduitHelper
[Git Source](https://github.com/AstariaXYZ/starport/blob/62254f50a959b2db00a7aa352d8f4d9e5269a8bb/src/ConduitHelper.sol)


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

