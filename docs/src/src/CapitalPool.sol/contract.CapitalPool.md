# CapitalPool
[Git Source](https://github.com/AstariaXYZ/starport/blob/62254f50a959b2db00a7aa352d8f4d9e5269a8bb/src/CapitalPool.sol)

**Inherits:**
ERC4626


## State Variables
### underlying

```solidity
address immutable underlying;
```


### conduitKey

```solidity
bytes32 conduitKey;
```


### conduit

```solidity
address public immutable conduit;
```


## Functions
### constructor


```solidity
constructor(address underlying_, ConduitControllerInterface cc_, address originator_);
```

### asset


```solidity
function asset() public view override returns (address);
```

### name


```solidity
function name() public pure override returns (string memory);
```

### symbol


```solidity
function symbol() public pure override returns (string memory);
```

### onERC721Received


```solidity
function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
  public
  pure
  returns (bytes4);
```

