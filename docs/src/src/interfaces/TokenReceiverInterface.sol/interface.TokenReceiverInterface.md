# TokenReceiverInterface
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/interfaces/TokenReceiverInterface.sol)


## Functions
### onERC721Received


```solidity
function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
    external
    returns (bytes4);
```

### onERC1155Received


```solidity
function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4);
```

### onERC1155BatchReceived


```solidity
function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
    external
    returns (bytes4);
```

