pragma solidity =0.8.17;

import {
    ItemType,
    SpentItem,
    ReceivedItem,
    OfferItem,
    ConsiderationItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Cast} from "starport-test/utils/Cast.sol";
import "starport-test/utils/FuzzStructs.sol" as Fuzz;
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

abstract contract Bound is StdUtils {
    VmSafe private constant vm = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    using Cast for *;

    mapping(uint256 => bool) public used;

    function _boundItemType(uint8 itemType) internal view returns (ItemType) {
        return _bound(itemType, uint8(ItemType.ERC20), uint8(ItemType.ERC1155)).toItemType();
    }

    function _boundTokenByItemType(ItemType itemType) internal view virtual returns (address);

    function _boundSpentItem(Fuzz.SpentItem memory input) internal returns (SpentItem memory ret) {
        ItemType itemType = _boundItemType(input.itemType);
        address token = _boundTokenByItemType(itemType);
        if (itemType == ItemType.ERC721) {
            input.identifier = _boundMin(4, type(uint256).max);
            if (used[input.identifier]) {
                bool goUp = true;
                if (input.identifier == type(uint256).max) {
                    goUp = false;
                }
                while (true) {
                    if (goUp) {
                        input.identifier++;
                        if (input.identifier == type(uint256).max) {
                            goUp = false;
                        }
                    } else {
                        input.identifier--;
                    }
                    if (!used[input.identifier]) {
                        break;
                    }
                }
            }
            input.amount = 1;
            used[input.identifier] = true;
        } else if (itemType == ItemType.ERC20) {
            input.identifier = 0;
            input.amount = _boundMin(1, 1_000_000 ether);
        } else if (itemType == ItemType.ERC1155) {
            input.amount = _boundMin(1, 1_000_000 ether);
        }

        ret = SpentItem({itemType: itemType, token: token, identifier: input.identifier, amount: input.amount});
    }

    function _boundSpentItems(Fuzz.SpentItem[] memory input) internal returns (SpentItem[] memory ret) {
        ret = new SpentItem[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            ret[i] = _boundSpentItem(input[i]);
        }
    }

    function _boundReceivedItem(Fuzz.ReceivedItem memory input) internal view returns (ReceivedItem memory ret) {
        ItemType itemType = _boundItemType(input.itemType);
        address token = _boundTokenByItemType(itemType);
        ret = ReceivedItem({
            itemType: itemType,
            token: token,
            identifier: input.identifier,
            amount: input.amount,
            recipient: input.recipient
        });
    }

    function _boundReceivedItems(Fuzz.ReceivedItem[] memory input) internal view returns (ReceivedItem[] memory ret) {
        vm.assume(input.length <= 4);
        ret = new ReceivedItem[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            ret[i] = _boundReceivedItem(input[i]);
        }
    }

    function _boundMin(uint256 value, uint256 min) internal view returns (uint256) {
        return _bound(value, min, type(uint256).max);
    }

    function _boundMinBytes32(uint256 value, uint256 min) internal view returns (bytes32) {
        return bytes32(_bound(value, min, type(uint256).max));
    }

    function _boundMax(uint256 value, uint256 max) internal view returns (uint256) {
        return _bound(value, 0, max);
    }

    function _boundNonZero(uint256 value) internal view returns (uint256) {
        return _boundMin(value, 1);
    }

    function _toUint(address value) internal view returns (uint256 output) {
        assembly ("memory-safe") {
            output := value
        }
    }

    function _toAddress(uint256 value) internal view returns (address output) {
        assembly ("memory-safe") {
            output := value
        }
    }

    function _boundNonZero(address value) internal view returns (address) {
        return _toAddress(_boundMin(_toUint(value), 1));
    }
}
