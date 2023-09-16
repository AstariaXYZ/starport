# FixedTermHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/hooks/FixedTermHook.sol)

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

