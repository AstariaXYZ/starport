# AstariaV1SettlementHook
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/hooks/AstariaV1SettlementHook.sol)

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

