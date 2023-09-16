# StarPortLib
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/lib/StarPortLib.sol)


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

