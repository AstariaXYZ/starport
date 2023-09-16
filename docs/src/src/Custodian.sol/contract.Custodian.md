# Custodian
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/Custodian.sol)

**Inherits:**
ContractOffererInterface, [TokenReceiverInterface](/src/interfaces/TokenReceiverInterface.sol/interface.TokenReceiverInterface.md), [ConduitHelper](/src/ConduitHelper.sol/abstract.ConduitHelper.md)


## State Variables
### LM

```solidity
LoanManager public immutable LM;
```


### seaport

```solidity
address public immutable seaport;
```


## Functions
### constructor


```solidity
constructor(LoanManager LM_, address seaport_);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view virtual override(ContractOffererInterface) returns (bool);
```

### onlySeaport


```solidity
modifier onlySeaport();
```

### ratifyOrder

*Generates the order for this contract offerer.*


```solidity
function ratifyOrder(
    SpentItem[] calldata offer,
    ReceivedItem[] calldata consideration,
    bytes calldata context,
    bytes32[] calldata orderHashes,
    uint256 contractNonce
) external onlySeaport returns (bytes4 ratifyOrderMagicValue);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`offer`|`SpentItem[]`|           The address of the contract fulfiller.|
|`consideration`|`ReceivedItem[]`|   The maximum amount of items to be spent by the order.|
|`context`|`bytes`|         The context of the order.|
|`orderHashes`|`bytes32[]`|     The context of the order.|
|`contractNonce`|`uint256`|   The context of the order.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`ratifyOrderMagicValue`|`bytes4`|The magic value returned by the ratify.|


### custody


```solidity
function custody(
    ReceivedItem[] calldata consideration,
    bytes32[] calldata orderHashes,
    uint256 contractNonce,
    bytes calldata context
) external virtual returns (bytes4 selector);
```

### generateOrder

*Generates the order for this contract offerer.*


```solidity
function generateOrder(
    address fulfiller,
    SpentItem[] calldata minimumReceived,
    SpentItem[] calldata maximumSpent,
    bytes calldata context
) external onlySeaport returns (SpentItem[] memory offer, ReceivedItem[] memory consideration);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`fulfiller`|`address`|       The address of the contract fulfiller.|
|`minimumReceived`|`SpentItem[]`||
|`maximumSpent`|`SpentItem[]`|    The maximum amount of items to be spent by the order.|
|`context`|`bytes`|         The context of the order.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`offer`|`SpentItem[]`|          The items spent by the order.|
|`consideration`|`ReceivedItem[]`|  The items received by the order.|


### _beforeApprovalsSetHook


```solidity
function _beforeApprovalsSetHook(address fulfiller, SpentItem[] calldata maximumSpent, bytes calldata context)
    internal
    virtual;
```

### _beforeSettlementHandlerHook


```solidity
function _beforeSettlementHandlerHook(LoanManager.Loan memory loan) internal virtual;
```

### _afterSettlementHandlerHook


```solidity
function _afterSettlementHandlerHook(LoanManager.Loan memory loan) internal virtual;
```

### _beforeSettleLoanHook


```solidity
function _beforeSettleLoanHook(LoanManager.Loan memory loan) internal virtual;
```

### _afterSettleLoanHook


```solidity
function _afterSettleLoanHook(LoanManager.Loan memory loan) internal virtual;
```

### _setOfferApprovals


```solidity
function _setOfferApprovals(SpentItem[] memory offer, address target) internal;
```

### previewOrder

*previews the order for this contract offerer.*


```solidity
function previewOrder(
    address caller,
    address fulfiller,
    SpentItem[] calldata minimumReceived,
    SpentItem[] calldata maximumSpent,
    bytes calldata context
) public view returns (SpentItem[] memory offer, ReceivedItem[] memory consideration);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`caller`|`address`|       The address of the contract fulfiller.|
|`fulfiller`|`address`|       The address of the contract fulfiller.|
|`minimumReceived`|`SpentItem[]`| The minimum the fulfiller must receive.|
|`maximumSpent`|`SpentItem[]`|    The most a fulfiller will spend|
|`context`|`bytes`|         The context of the order.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`offer`|`SpentItem[]`|    The items spent by the order.|
|`consideration`|`ReceivedItem[]`| The items received by the order.|


### getSeaportMetadata


```solidity
function getSeaportMetadata() external pure returns (string memory, Schema[] memory schemas);
```

### onERC721Received


```solidity
function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
    public
    pure
    virtual
    returns (bytes4);
```

### onERC1155Received


```solidity
function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure virtual returns (bytes4);
```

### onERC1155BatchReceived


```solidity
function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
    external
    pure
    virtual
    returns (bytes4);
```

### _getBorrower


```solidity
function _getBorrower(LoanManager.Loan memory loan) internal view virtual returns (address);
```

### _settleLoan


```solidity
function _settleLoan(LoanManager.Loan memory loan) internal virtual;
```

## Events
### SeaportCompatibleContractDeployed

```solidity
event SeaportCompatibleContractDeployed();
```

## Errors
### InvalidSender

```solidity
error InvalidSender();
```

### InvalidHandler

```solidity
error InvalidHandler();
```

