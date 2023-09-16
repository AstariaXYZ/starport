# StarPortLib
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/lib/StarPortLib.sol)


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

