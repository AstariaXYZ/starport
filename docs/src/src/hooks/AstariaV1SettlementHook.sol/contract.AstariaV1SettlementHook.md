# AstariaV1SettlementHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/hooks/AstariaV1SettlementHook.sol)

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

