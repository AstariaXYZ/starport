# FixedRateEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/e51acaefbeb55ecb95b59095c9d800c6e8ce36a5/src/enforcers/RateEnforcer.sol)

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

