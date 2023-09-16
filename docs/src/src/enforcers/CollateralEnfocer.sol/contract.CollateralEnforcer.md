# CollateralEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/enforcers/CollateralEnfocer.sol)

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

