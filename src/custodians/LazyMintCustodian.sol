pragma solidity ^0.8.17;

import "../Custodian.sol";
import {ERC721} from "solady/src/tokens/ERC721.sol";

contract LazyMintCustodian is Custodian, ERC721 {
    constructor(LoanManager LM_, address seaport_) Custodian(LM_, seaport_) {}

    function _getBorrower(LoanManager.Loan memory loan) internal view override returns (address) {
        uint256 loanId = uint256(keccak256(abi.encode(loan)));
        return _exists(loanId) ? ownerOf(loanId) : loan.borrower;
    }

    function mint(LoanManager.Loan calldata loan) external {
        bytes memory encodedLoan = abi.encode(loan);
        uint256 loanId = uint256(keccak256(encodedLoan));
        _safeMint(loan.issuer, loanId, encodedLoan);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked("https://astaria.xyz/custodian/", address(this), string("/"), tokenId));
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, Custodian) returns (bool) {
        return ERC721.supportsInterface(interfaceId)
        //      interfaceId == type(this).interfaceId ||
        //      interfaceId == type(LazyMintCustodian).interfaceId ||
        || super.supportsInterface(interfaceId);
    }

    function _beforeSettleLoanHook(LoanManager.Loan memory loan) internal override {
        _burn(uint256(keccak256(abi.encode(loan))));
    }

    function name() public pure override returns (string memory) {
        return "Astaria Custodian Token";
    }

    function symbol() public pure override returns (string memory) {
        return "ACT";
    }
}
