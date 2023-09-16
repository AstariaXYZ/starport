# CollateralEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/e51acaefbeb55ecb95b59095c9d800c6e8ce36a5/src/enforcers/CollateralEnfocer.sol)

**Inherits:**
[CaveatEnforcer](/src/enforcers/CaveatEnforcer.sol/abstract.CaveatEnforcer.md)


## Functions
### enforceCaveat


```solidity
function enforceCaveat(bytes calldata terms, LoanManager.Loan memory loan) public view override returns (bool valid);
```

## Structs
### Details

```solidity
struct Details {
    SpentItem[] collateral;
    bool isAny;
}
```

