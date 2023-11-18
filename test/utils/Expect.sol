import {ItemType, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import "forge-std/Test.sol";

abstract contract Expect is Test {
    ItemType MAX_ITEM_TYPE = ItemType.ERC1155_WITH_CRITERIA;

    function _expectRevert(SpentItem[] calldata items) internal {
        bool expectRevert;
        ItemType max = type(ItemType).max;
        assembly ("memory-safe") {
            let e := add(items.offset, mul(items.length, 0x80))

            for { let i := items.offset } lt(i, e) { i := add(i, 0x80) } {
                let item := calldataload(i)
                if gt(item, max) {
                    expectRevert := 1
                    break
                }
            }
        }

        if (expectRevert) {
            vm.expectRevert();
        }
    }
}
