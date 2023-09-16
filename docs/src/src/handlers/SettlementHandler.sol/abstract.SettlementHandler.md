# SettlementHandler
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/handlers/SettlementHandler.sol)


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

