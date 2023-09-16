# AstariaV1SettlementHandler
[Git Source](https://github.com/AstariaXYZ/starport/blob/579f2b696f3db97ba152a0f0d28350598ebf1089/src/handlers/AstariaV1SettlementHandler.sol)

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

