# Pricing
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/pricing/Pricing.sol)


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

