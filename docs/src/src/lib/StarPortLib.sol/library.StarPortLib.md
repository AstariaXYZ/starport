# StarPortLib
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/lib/StarPortLib.sol)


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

