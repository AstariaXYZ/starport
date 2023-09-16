# CollateralEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/enforcers/CollateralEnfocer.sol)

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

