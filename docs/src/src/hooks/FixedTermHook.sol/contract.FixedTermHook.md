# FixedTermHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/579f2b696f3db97ba152a0f0d28350598ebf1089/src/hooks/FixedTermHook.sol)

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

