# AstariaV1Pricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/pricing/AstariaV1Pricing.sol)

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

