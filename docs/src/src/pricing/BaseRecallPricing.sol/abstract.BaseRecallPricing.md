# BaseRecallPricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/pricing/BaseRecallPricing.sol)

**Inherits:**
[BasePricing](/src/pricing/BasePricing.sol/abstract.BasePricing.md)


## Functions
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

