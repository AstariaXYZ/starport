pragma solidity ^0.8.17;

import {TestERC721} from "seaport/contracts/test/TestERC721.sol";

contract MockERC721 is TestERC721 {
    constructor() TestERC721() {}
}
