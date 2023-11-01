pragma solidity ^0.8.17;

import {TestERC20} from "seaport/contracts/test/TestERC20.sol";

contract MockERC20 is TestERC20 {
    constructor() TestERC20() {}
}
