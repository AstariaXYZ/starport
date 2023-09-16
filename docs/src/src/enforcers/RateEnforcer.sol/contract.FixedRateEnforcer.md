# FixedRateEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/579f2b696f3db97ba152a0f0d28350598ebf1089/src/enforcers/RateEnforcer.sol)

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

