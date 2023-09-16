# FixedRateEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/enforcers/RateEnforcer.sol)

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

