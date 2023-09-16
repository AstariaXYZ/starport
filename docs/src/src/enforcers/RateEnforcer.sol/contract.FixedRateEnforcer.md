# FixedRateEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/enforcers/RateEnforcer.sol)

**Inherits:**
[CaveatEnforcer](/src/enforcers/CaveatEnforcer.sol/abstract.CaveatEnforcer.md)


## Functions
### enforceCaveat


```solidity
function enforceCaveat(bytes calldata caveatTerms, LoanManager.Loan memory loan) public view override returns (bool);
```

## Structs
### Details

```solidity
struct Details {
    uint256 maxRate;
    uint256 maxCarryRate;
}
```

