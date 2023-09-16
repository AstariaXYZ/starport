# Pricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/e51acaefbeb55ecb95b59095c9d800c6e8ce36a5/src/pricing/Pricing.sol)


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

