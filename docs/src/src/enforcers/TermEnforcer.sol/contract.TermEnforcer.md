# TermEnforcer
[Git Source](https://github.com/AstariaXYZ/starport/blob/579f2b696f3db97ba152a0f0d28350598ebf1089/src/enforcers/TermEnforcer.sol)

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

