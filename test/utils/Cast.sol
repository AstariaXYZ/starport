pragma solidity =0.8.17;

import {ItemType, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import "test/utils/FuzzStructs.sol" as Fuzz;
import "forge-std/Test.sol";

library Cast {
    function toUint(uint8 input) internal pure returns (uint256 ret) {
        assembly {
            ret := input
        }
    }

    function toUint(address input) internal pure returns (uint256 ret) {
        assembly {
            ret := input
        }
    }

    function toItemType(uint256 input) internal pure returns (ItemType ret) {
        assembly {
            ret := input
        }
    }
}
