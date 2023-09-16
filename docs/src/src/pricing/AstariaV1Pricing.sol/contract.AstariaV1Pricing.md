# AstariaV1Pricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/pricing/AstariaV1Pricing.sol)

**Inherits:**
[CompoundInterestPricing](/src/pricing/CompoundInterestPricing.sol/abstract.CompoundInterestPricing.md)


## Functions
### constructor


```solidity
constructor(LoanManager LM_) Pricing(LM_);
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
        ReceivedItem[] memory recallConsideration
    );
```

## Errors
### InsufficientRefinance

```solidity
error InsufficientRefinance();
```

