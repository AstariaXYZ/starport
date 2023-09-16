# StarPortLib
[Git Source](https://github.com/AstariaXYZ/starport/blob/579f2b696f3db97ba152a0f0d28350598ebf1089/src/lib/StarPortLib.sol)


## Functions
### getId


```solidity
function getId(LoanManager.Loan memory loan) internal pure returns (uint256 loanId);
```

### toReceivedItems


```solidity
function toReceivedItems(SpentItem[] calldata spentItems, address recipient)
    internal
    pure
    returns (ReceivedItem[] memory result);
```

### encodeWithRecipient


```solidity
function encodeWithRecipient(ReceivedItem[] calldata receivedItems, address recipient)
    internal
    pure
    returns (ReceivedItem[] memory result);
```

