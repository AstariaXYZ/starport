# SimpleInterestPricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/pricing/SimpleInterestPricing.sol)

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

