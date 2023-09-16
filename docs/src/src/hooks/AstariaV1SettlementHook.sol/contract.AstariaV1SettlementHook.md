# AstariaV1SettlementHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/hooks/AstariaV1SettlementHook.sol)

**Inherits:**
[BaseHook](/src/hooks/BaseHook.sol/abstract.BaseHook.md), [BaseRecall](/src/hooks/BaseRecall.sol/abstract.BaseRecall.md)


## Functions
### constructor


```solidity
constructor(LoanManager LM_) BaseRecall(LM_);
```

### isActive


```solidity
function isActive(LoanManager.Loan calldata loan) external view override returns (bool);
```

### isRecalled


```solidity
function isRecalled(LoanManager.Loan calldata loan) external view override returns (bool);
```

