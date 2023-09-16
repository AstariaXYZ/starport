# SettlementHandler
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/handlers/SettlementHandler.sol)


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

