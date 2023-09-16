# AstariaV1SettlementHandler
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/handlers/AstariaV1SettlementHandler.sol)

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

