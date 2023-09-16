# StarPortLib
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/lib/StarPortLib.sol)


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

