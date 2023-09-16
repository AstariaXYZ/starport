# FixedRateEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/enforcers/RateEnforcer.sol)

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

