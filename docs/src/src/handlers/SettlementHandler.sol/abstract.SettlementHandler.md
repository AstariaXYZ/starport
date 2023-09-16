# SettlementHandler
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/handlers/SettlementHandler.sol)


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

### execute


```solidity
function execute(LoanManager.Loan calldata loan) external virtual returns (bytes4);
```

### validate


```solidity
function validate(LoanManager.Loan calldata loan) external view virtual returns (bool);
```

### getSettlement


```solidity
function getSettlement(LoanManager.Loan memory loan)
    external
    virtual
    returns (ReceivedItem[] memory consideration, address restricted);
```

