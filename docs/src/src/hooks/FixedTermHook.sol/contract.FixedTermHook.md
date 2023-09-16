# FixedTermHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/hooks/FixedTermHook.sol)

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

