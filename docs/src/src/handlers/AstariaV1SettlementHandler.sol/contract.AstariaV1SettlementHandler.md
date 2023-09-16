# AstariaV1SettlementHandler
[Git Source](https://github.com/AstariaXYZ/starport/blob/15aa42a21bd8713473a3e2d3f09c004e943dc663/src/handlers/AstariaV1SettlementHandler.sol)

**Inherits:**
[DutchAuctionHandler](/src/handlers/DutchAuctionHandler.sol/contract.DutchAuctionHandler.md)


## Functions
### constructor


```solidity
constructor(LoanManager LM_) DutchAuctionHandler(LM_);
```

### getSettlement


```solidity
function getSettlement(LoanManager.Loan memory loan)
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory, address restricted);
```

### validate


```solidity
function validate(LoanManager.Loan calldata loan) external view virtual override returns (bool);
```

