# AstariaV1Pricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/62254f50a959b2db00a7aa352d8f4d9e5269a8bb/src/pricing/AstariaV1Pricing.sol)

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

