# LazyMintCustodian
[Git Source](https://github.com/AstariaXYZ/starport/blob/3b5262d09059b9ae5a2377a67d883d25f8ae5aab/src/custodians/LazyMintCustodian.sol)

**Inherits:**
[Custodian](/src/Custodian.sol/contract.Custodian.md), ERC721


## Functions
### constructor


```solidity
constructor(LoanManager LM_, address seaport_) Custodian(LM_, seaport_);
```

### _getBorrower


```solidity
function _getBorrower(LoanManager.Loan memory loan) internal view override returns (address);
```

### mint


```solidity
function mint(LoanManager.Loan calldata loan) external;
```

### tokenURI


```solidity
function tokenURI(uint256 tokenId) public view override returns (string memory);
```

### supportsInterface


```solidity
function supportsInterface(bytes4 interfaceId) public view override(ERC721, Custodian) returns (bool);
```

### _beforeSettleLoanHook


```solidity
function _beforeSettleLoanHook(LoanManager.Loan memory loan) internal override;
```

### name


```solidity
function name() public pure override returns (string memory);
```

### symbol


```solidity
function symbol() public pure override returns (string memory);
```

