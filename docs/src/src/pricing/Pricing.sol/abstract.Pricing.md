# Pricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/pricing/Pricing.sol)


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

