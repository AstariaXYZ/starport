# TermEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/enforcers/TermEnforcer.sol)

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
    address pricing;
    address hook;
    address handler;
}
```

