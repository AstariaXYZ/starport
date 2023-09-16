# MerkleOriginator
[Git Source](https://github.com/AstariaXYZ/starport/blob/75a84b0e30f9e2164d22fbf3939027de06a1ea1a/src/originators/MerkleOriginator.sol)

**Inherits:**
[Originator](/src/originators/Originator.sol/abstract.Originator.md)


## Functions
### constructor


```solidity
constructor(LoanManager LM_, address strategist_, uint256 fee_) Originator(LM_, strategist_, fee_);
```

### terms


```solidity
function terms(bytes calldata details) public view override returns (LoanManager.Terms memory);
```

### _build


```solidity
function _build(Request calldata params, Details memory details) internal view returns (Response memory response);
```

### _validateMerkleProof


```solidity
function _validateMerkleProof(MerkleProof memory incomingMerkleProof, bytes32 leafHash) internal view virtual;
```

### execute


```solidity
function execute(Request calldata params) external override returns (Response memory response);
```

### _validateAsk


```solidity
function _validateAsk(Request calldata request, Details memory details) internal;
```

### getFeeConsideration


```solidity
function getFeeConsideration(LoanManager.Loan calldata loan)
    external
    view
    override
    returns (ReceivedItem[] memory consideration);
```

## Errors
### InvalidMerkleProof

```solidity
error InvalidMerkleProof();
```

## Structs
### MerkleProof

```solidity
struct MerkleProof {
    bytes32 root;
    bytes32[] proof;
}
```

### Details

```solidity
struct Details {
    address custodian;
    address conduit;
    address issuer;
    uint256 deadline;
    LoanManager.Terms terms;
    SpentItem[] collateral;
    SpentItem[] debt;
    bytes validator;
}
```

