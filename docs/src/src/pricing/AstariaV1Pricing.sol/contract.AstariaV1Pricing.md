# AstariaV1Pricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/pricing/AstariaV1Pricing.sol)

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

