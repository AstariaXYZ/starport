# DutchAuctionHandler
[Git Source](https://github.com/AstariaXYZ/starport/blob/22f00b954c780c3e2d90e9d0a8f83c4a2a3060ff/src/handlers/DutchAuctionHandler.sol)

**Inherits:**
[SettlementHandler](/src/handlers/SettlementHandler.sol/abstract.SettlementHandler.md), AmountDeriver, [ConduitHelper](/src/ConduitHelper.sol/abstract.ConduitHelper.md)


## Functions
### constructor


```solidity
constructor(LoanManager LM_) SettlementHandler(LM_);
```

### getSettlement


```solidity
function getSettlement(LoanManager.Loan memory loan)
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory consideration, address restricted);
```

### validate


```solidity
function validate(LoanManager.Loan calldata loan) external view virtual override returns (bool);
```

## Errors
### InvalidAmount

```solidity
error InvalidAmount();
```

## Structs
### Details

```solidity
struct Details {
    uint256 startingPrice;
    uint256 endingPrice;
    uint256 window;
}
```

