# FixedTermHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/hooks/FixedTermHook.sol)

**Inherits:**
[SettlementHook](/src/hooks/SettlementHook.sol/abstract.SettlementHook.md)


## Functions
### isActive


```solidity
function isActive(LoanManager.Loan calldata loan) external view override returns (bool);
```

## Structs
### Details

```solidity
struct Details {
    uint256 loanDuration;
}
```

