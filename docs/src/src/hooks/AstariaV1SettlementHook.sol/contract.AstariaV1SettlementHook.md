# AstariaV1SettlementHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/62254f50a959b2db00a7aa352d8f4d9e5269a8bb/src/hooks/AstariaV1SettlementHook.sol)

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

