pragma solidity 0.8.17;

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

library StarLiteLib {
    function toReceivedItems(SpentItem[] calldata spentItems, address recipient)
        internal
        pure
        returns (ReceivedItem[] memory result)
    {
        assembly {
            //set `result` pointer to free memory
            result := mload(0x40)

            let n := spentItems.length

            //store length of `result`
            mstore(result, n)

            //set `ptr` to start of first struct offset
            let ptr := add(result, 0x20)

            //`s` = offset of first struct
            let s := add(ptr, mul(n, 0x20))

            //expand memory
            mstore(0x40, add(ptr, mul(n, 0xC0)))

            //store struct offsets - first offset starts at end of offsets
            let o := s
            let c := spentItems.offset
            let r := add(s, 0x80) // first recipient offset
            for {} lt(ptr, s) {
                ptr := add(ptr, 0x20)
                c := add(c, 0x80)
                o := add(o, 0xA0)
                r := add(r, 0xA0)
            } {
                mstore(ptr, o) //store offset
                calldatacopy(o, c, 0x80)
                mstore(r, recipient) //set recipient
            }
        }
    }

    function encodeWithRecipient(ReceivedItem[] calldata receivedItems, address recipient)
        internal
        pure
        returns (ReceivedItem[] memory result)
    {
        assembly {
            //set `result` pointer to free memory
            result := mload(0x40)

            let n := receivedItems.length

            //store length of `result`
            mstore(result, n)

            //set `ptr` to start of first struct offset
            let ptr := add(result, 0x20)

            //`s` = offset of first struct
            let s := add(ptr, mul(n, 0x20))

            //expand memory
            mstore(0x40, add(ptr, mul(n, 0xC0)))

            //copy struct data
            calldatacopy(s, receivedItems.offset, mul(n, 0xA0))

            //store struct offsets - first offset starts at end of offsets
            let o := s
            let r := add(s, 0x80) // first recipient offset
            for {} lt(ptr, s) {
                ptr := add(ptr, 0x20)
                o := add(o, 0xA0)
                r := add(r, 0xA0)
            } {
                mstore(ptr, o) //store offset
                mstore(r, recipient) //set recipient
            }
        }
    }
}
