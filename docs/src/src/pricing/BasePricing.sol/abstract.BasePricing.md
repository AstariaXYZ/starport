# BasePricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/e51acaefbeb55ecb95b59095c9d800c6e8ce36a5/src/pricing/BasePricing.sol)

**Inherits:**
[Pricing](/src/pricing/Pricing.sol/abstract.Pricing.md)


## Functions
### getPaymentConsideration


```solidity
function getPaymentConsideration(LoanManager.Loan memory loan)
    public
    view
    virtual
    override
    returns (ReceivedItem[] memory repayConsideration, ReceivedItem[] memory carryConsideration);
```

### getOwed


```solidity
function getOwed(LoanManager.Loan memory loan) public view returns (uint256[] memory);
```

### _getOwedCarry


```solidity
function _getOwedCarry(LoanManager.Loan memory loan, Details memory details, uint256 timestamp)
    internal
    view
    returns (uint256[] memory carryOwed);
```

### _getOwed


```solidity
function _getOwed(LoanManager.Loan memory loan, Details memory details, uint256 start, uint256 end)
    internal
    view
    returns (uint256[] memory updatedDebt);
```

### getInterest


```solidity
function getInterest(LoanManager.Loan memory loan, Details memory details, uint256 start, uint256 end, uint256 index)
    public
    view
    returns (uint256);
```

### calculateInterest


```solidity
function calculateInterest(uint256 delta_t, uint256 amount, uint256 rate) public pure virtual returns (uint256);
```

### _generateRepayConsideration


```solidity
function _generateRepayConsideration(LoanManager.Loan memory loan)
    internal
    view
    returns (ReceivedItem[] memory consideration);
```

### _generateRepayCarryConsideration


```solidity
function _generateRepayCarryConsideration(LoanManager.Loan memory loan)
    internal
    view
    returns (ReceivedItem[] memory consideration);
```

## Structs
### Details

```solidity
struct Details {
    uint256 rate;
    uint256 carryRate;
}
```

