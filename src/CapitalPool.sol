pragma solidity ^0.8.17;

import {ERC20, ERC4626} from "solady/src/tokens/ERC4626.sol";
import {LoanManager} from "src/LoanManager.sol";
import {
  ConduitControllerInterface
} from "seaport-sol/src/ConduitControllerInterface.sol";

import "forge-std/console.sol";

contract CapitalPool is ERC4626 {
  address immutable underlying;

  bytes32 conduitKey;
  address public immutable conduit;

  constructor(
    address underlying_,
    ConduitControllerInterface cc_,
    address originator_
  ) {
    bytes32 ck = bytes32(uint256(uint160(address(address(this)))) << 96);
    address c = cc_.createConduit(ck, address(this));
    cc_.updateChannel(c, originator_, true);
    ERC20(underlying_).approve(c, type(uint256).max);
    conduit = c;
    conduitKey = ck;
    underlying = underlying_;
  }

  function asset() public view override returns (address) {
    return underlying;
  }

  function name() public pure override returns (string memory) {
    return "AstariaV1Pool";
  }

  function symbol() public pure override returns (string memory) {
    return "AV1P";
  }

  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) public pure returns (bytes4) {
    LoanManager.Loan memory loan = abi.decode(data, (LoanManager.Loan));
    //handle any logic here from when you receive a loan
    return this.onERC721Received.selector;
  }
}
