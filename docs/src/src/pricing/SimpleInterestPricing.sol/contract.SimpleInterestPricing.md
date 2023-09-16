# SimpleInterestPricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/pricing/SimpleInterestPricing.sol)

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

