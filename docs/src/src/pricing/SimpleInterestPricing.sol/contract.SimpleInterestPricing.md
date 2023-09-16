# SimpleInterestPricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/pricing/SimpleInterestPricing.sol)

**Inherits:**
[BasePricing](/src/pricing/BasePricing.sol/abstract.BasePricing.md)


## Functions
### constructor


```solidity
constructor(LoanManager LM_) Pricing(LM_);
```

### calculateInterest


```solidity
function calculateInterest(uint256 delta_t, uint256 amount, uint256 rate) public pure override returns (uint256);
```

### isValidRefinance


```solidity
function isValidRefinance(LoanManager.Loan memory loan, bytes memory newPricingData, address caller)
    external
    view
    virtual
    override
    returns (
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsideration
    );
```

