# FixedTermHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/hooks/FixedTermHook.sol)

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

