# LoanManager
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/LoanManager.sol)

**Inherits:**
ERC721, ContractOffererInterface, [ConduitHelper](/src/ConduitHelper.sol/abstract.ConduitHelper.md)


## State Variables
### seaport

```solidity
ConsiderationInterface public constant seaport = ConsiderationInterface(0x2e234DAe75C793f67A35089C9d99245E1C58470b);
```


### defaultCustodian

```solidity
address public immutable defaultCustodian;
```


### DEFAULT_CUSTODIAN_CODE_HASH

```solidity
bytes32 public immutable DEFAULT_CUSTODIAN_CODE_HASH;
```


### EIP_DOMAIN

```solidity
bytes32 constant EIP_DOMAIN = keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
```


### INTENT_ORIGINATION_TYPEHASH

```solidity
bytes32 public constant INTENT_ORIGINATION_TYPEHASH =
    keccak256("IntentOrigination(bytes32 hash,bytes32 salt,uint256 nonce)");
```


### VERSION

```solidity
bytes32 constant VERSION = keccak256("0");
```


### _DOMAIN_SEPARATOR

```solidity
bytes32 internal immutable _DOMAIN_SEPARATOR;
```


### usedHashes

```solidity
mapping(bytes32 => bool) public usedHashes;
```


### borrowerNonce

```solidity
mapping(address => uint256) public borrowerNonce;
```


## Functions
### constructor


```solidity
constructor();
```

### encodeWithSaltAndBorrowerCounter


```solidity
function encodeWithSaltAndBorrowerCounter(address borrower, bytes32 salt, bytes32 caveatHash)
    public
    view
    virtual
    returns (bytes memory);
```

### name


```solidity
function name() public pure override returns (string memory);
```

### symbol


```solidity
function symbol() public pure override returns (string memory);
```

### onlySeaport


```solidity
modifier onlySeaport();
```

### active


```solidity
function active(uint256 loanId) public view returns (bool);
```

### inactive


```solidity
function inactive(uint256 loanId) public view returns (bool);
```

### initialized


```solidity
function initialized(uint256 loanId) public view returns (bool);
```

### tokenURI


```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory);
```

### _issued


```solidity
function _issued(uint256 tokenId) internal view returns (bool);
```

### issued


```solidity
function issued(uint256 tokenId) external view returns (bool);
```

### ownerOf


```solidity
function ownerOf(uint256 loanId) public view override returns (address);
```

### settle


```solidity
function settle(Loan memory loan) external;
```

### _settle


```solidity
function _settle(Loan memory loan) internal;
```

### _callCustody


```solidity
function _callCustody(
    ReceivedItem[] calldata consideration,
    bytes32[] calldata orderHashes,
    uint256 contractNonce,
    bytes calldata context
) internal returns (bytes4 selector);
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

*Gets the metadata for this contract offerer.*


```solidity
function getSeaportMetadata() external pure returns (string memory, Schema[] memory schemas);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`string`|name    The name of the contract offerer.|
|`schemas`|`Schema[]`|The schemas supported by the contract offerer.|


### _fillObligationAndVerify


```solidity
function _fillObligationAndVerify(
    address fulfiller,
    LoanManager.Obligation memory obligation,
    SpentItem[] calldata maximumSpentFromBorrower
) internal returns (SpentItem[] memory offer);
```

### _issueLoanManager


```solidity
function _issueLoanManager(Loan memory loan, bool mint) internal;
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


### _setDebtApprovals


```solidity
function _setDebtApprovals(SpentItem memory debt) internal;
```

### _setOffer


```solidity
function _setOffer(SpentItem[] memory debt, bytes32 caveatHash) internal returns (SpentItem[] memory offer);
```

### transferFrom


```solidity
function transferFrom(address from, address to, uint256 tokenId) public payable override;
```

### safeTransferFrom


```solidity
function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) public payable override;
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


### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721, ContractOffererInterface)
    returns (bool);
```

### refinance


```solidity
function refinance(LoanManager.Loan memory loan, bytes memory newPricingData, address conduit) external;
```

## Events
### Close

```solidity
event Close(uint256 loanId);
```

### Open

```solidity
event Open(uint256 loanId, LoanManager.Loan loan);
```

### SeaportCompatibleContractDeployed

```solidity
event SeaportCompatibleContractDeployed();
```

## Errors
### ConduitTransferError

```solidity
error ConduitTransferError();
```

### InvalidConduit

```solidity
error InvalidConduit();
```

### InvalidRefinance

```solidity
error InvalidRefinance();
```

### InvalidSender

```solidity
error InvalidSender();
```

### InvalidAction

```solidity
error InvalidAction();
```

### InvalidLoan

```solidity
error InvalidLoan(uint256);
```

### InvalidMaximumSpentEmpty

```solidity
error InvalidMaximumSpentEmpty();
```

### InvalidDebtEmpty

```solidity
error InvalidDebtEmpty();
```

### InvalidAmount

```solidity
error InvalidAmount();
```

### InvalidDuration

```solidity
error InvalidDuration();
```

### InvalidSignature

```solidity
error InvalidSignature();
```

### InvalidOrigination

```solidity
error InvalidOrigination();
```

### InvalidSigner

```solidity
error InvalidSigner();
```

### InvalidContext

```solidity
error InvalidContext(ContextErrors);
```

### InvalidNoRefinanceConsideration

```solidity
error InvalidNoRefinanceConsideration();
```

## Structs
### Terms

```solidity
struct Terms {
    address hook;
    bytes hookData;
    address pricing;
    bytes pricingData;
    address handler;
    bytes handlerData;
}
```

### Loan

```solidity
struct Loan {
    uint256 start;
    address custodian;
    address borrower;
    address issuer;
    address originator;
    SpentItem[] collateral;
    SpentItem[] debt;
    Terms terms;
}
```

### Caveat

```solidity
struct Caveat {
    address enforcer;
    bytes terms;
}
```

### Obligation

```solidity
struct Obligation {
    address custodian;
    address originator;
    address borrower;
    bytes32 salt;
    SpentItem[] debt;
    Caveat[] caveats;
    bytes details;
    bytes signature;
}
```

## Enums
### FieldFlags

```solidity
enum FieldFlags {
    INITIALIZED,
    ACTIVE,
    INACTIVE
}
```

### ContextErrors

```solidity
enum ContextErrors {
    BAD_ORIGINATION,
    INVALID_PAYMENT,
    LENGTH_MISMATCH,
    BORROWER_MISMATCH,
    COLLATERAL,
    ZERO_ADDRESS,
    INVALID_LOAN,
    INVALID_CONDUIT,
    INVALID_RESOLVER,
    INVALID_COLLATERAL
}
```

