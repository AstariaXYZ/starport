# EnglishAuctionHandler
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/handlers/EnglishAuctionHandler.sol)

**Inherits:**
[SettlementHandler](/src/handlers/SettlementHandler.sol/abstract.SettlementHandler.md)


## State Variables
### consideration

```solidity
ConsiderationInterface consideration;
```


### ENGLISH_AUCTION_ZONE

```solidity
address public ENGLISH_AUCTION_ZONE;
```


### OS_RECEIVER

```solidity
address payable public constant OS_RECEIVER = payable(0x0000a26b00c1F0DF003000390027140000fAa719);
```


## Functions
### constructor


```solidity
constructor(LoanManager LM_, ConsiderationInterface consideration_, address EAZone_) SettlementHandler(LM_);
```

### validate


```solidity
function validate(LoanManager.Loan calldata loan) external view override returns (bool);
```

### execute


```solidity
function execute(LoanManager.Loan calldata loan) external virtual override returns (bytes4 selector);
```

### getSettlement


```solidity
function getSettlement(LoanManager.Loan memory loan)
    external
    view
    override
    returns (ReceivedItem[] memory consideration, address restricted);
```

### liquidate


```solidity
function liquidate(LoanManager.Loan calldata loan) external;
```

## Errors
### InvalidOrder

```solidity
error InvalidOrder();
```

## Structs
### Details

```solidity
struct Details {
    uint256[] reservePrice;
    uint256 window;
}
```

