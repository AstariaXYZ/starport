# Pricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/pricing/Pricing.sol)


## State Variables
### LM

```solidity
LoanManager LM;
```


## Functions
### constructor


```solidity
constructor(LoanManager LM_);
```

### getPaymentConsideration


```solidity
function getPaymentConsideration(LoanManager.Loan memory loan)
    public
    view
    virtual
    returns (ReceivedItem[] memory, ReceivedItem[] memory);
```

### isValidRefinance


```solidity
function isValidRefinance(LoanManager.Loan memory loan, bytes memory newPricingData, address caller)
    external
    view
    virtual
    returns (ReceivedItem[] memory, ReceivedItem[] memory, ReceivedItem[] memory);
```

## Errors
### InvalidRefinance

```solidity
error InvalidRefinance();
```

