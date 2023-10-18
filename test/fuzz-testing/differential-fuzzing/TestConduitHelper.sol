pragma solidity =0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {
    ConsiderationItem,
    AdvancedOrder,
    CriteriaResolver,
    OrderType
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Conduit} from "seaport-core/src/conduit/Conduit.sol";
import {ConduitController} from "seaport-core/src/conduit/ConduitController.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {ConduitHelper} from "starport-core/ConduitHelper.sol";
import {RefConduitHelper} from "starport-core/RefConduitHelper.sol";
import {Bound} from "starport-test/utils/Bound.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {Cast} from "starport-test/utils/Cast.sol";
import "starport-test/utils/FuzzStructs.sol" as Fuzz;

abstract contract BaseTestConduitHelper is Test, Bound, DeepEq {
    ReceivedItem[] receivedItems;

    using Cast for *;

    function _copy(ReceivedItem[] memory items) internal pure returns (ReceivedItem[] memory) {
        ReceivedItem[] memory copy = new ReceivedItem[](items.length);
        for (uint256 i = 0; i < items.length; ++i) {
            copy[i] = items[i];
        }
        return copy;
    }

    function _mergeAndRemoveZeroAmounts(ReceivedItem[] memory, ReceivedItem[] memory, ReceivedItem[] memory)
        internal
        virtual
        returns (ReceivedItem[] memory);

    function _countNonZeroAmounts(ReceivedItem[] memory, uint256) internal virtual returns (uint256);

    function testFuzzMergeAndRemoveZeroAmounts(
        Fuzz.ReceivedItem[] memory a,
        Fuzz.ReceivedItem[] memory b,
        Fuzz.ReceivedItem[] memory c
    ) public {
        ReceivedItem[] memory boundA = _boundReceivedItems(a);
        ReceivedItem[] memory boundB = _boundReceivedItems(b);
        ReceivedItem[] memory boundC = _boundReceivedItems(c);

        ReceivedItem[] memory boundATemp = _copy(boundA);
        ReceivedItem[] memory boundBTemp = _copy(boundB);
        ReceivedItem[] memory boundCTemp = _copy(boundC);

        uint256 validCount = _countNonZeroAmounts(boundA, 0);
        validCount = _countNonZeroAmounts(boundB, validCount);
        validCount = _countNonZeroAmounts(boundC, validCount);

        ReceivedItem[] memory actual = _mergeAndRemoveZeroAmounts(boundATemp, boundBTemp, boundCTemp);
        console.log("validCount: %s", validCount);
        console.log("actual.length: %s", actual.length);
        assertTrue(actual.length == validCount, "actual.length should be equal to validCount");
        console.log("boundA.length: %s", boundA.length);
        console.log("boundB.length: %s", boundB.length);
        console.log("boundC.length: %s", boundC.length);

        actual.toStorage(receivedItems);

        for (uint256 i = boundC.length; i > 0; --i) {
            ReceivedItem memory item = boundC[i - 1];
            if (item.amount == 0) {
                continue;
            }
            _deepEq(item, receivedItems[receivedItems.length - 1]);
            receivedItems.pop();
        }
        for (uint256 i = b.length; i > 0; --i) {
            ReceivedItem memory item = boundB[i - 1];
            if (item.amount == 0) {
                continue;
            }
            _deepEq(item, receivedItems[receivedItems.length - 1]);
            receivedItems.pop();
        }

        for (uint256 i = boundA.length; i > 0; --i) {
            ReceivedItem memory item = boundA[i - 1];
            if (item.amount == 0) {
                continue;
            }
            _deepEq(item, receivedItems[receivedItems.length - 1]);
            receivedItems.pop();
        }

        if (receivedItems.length != 0) {
            console.log(validCount);
            logConsideration(receivedItems);
            revert("receivedItems should be empty");
        }
    }

    function testMergeAndRemoveZeroAmounts() public {
        ReceivedItem[] memory receivedItemsA;
        ReceivedItem[] memory receivedItemsB;
        ReceivedItem[] memory receivedItemsC;
        (receivedItemsA, receivedItemsB, receivedItemsC) = getBenchArrays();

        uint256 validCount = _countNonZeroAmounts(receivedItemsA, 0);
        validCount = _countNonZeroAmounts(receivedItemsB, validCount);
        validCount = _countNonZeroAmounts(receivedItemsC, validCount);

        ReceivedItem[] memory consideration = _mergeAndRemoveZeroAmounts(receivedItemsA, receivedItemsB, receivedItemsC);

        logConsideration(consideration);

        assertEq(consideration.length, validCount, "consideration length should be equal to validCount");
    }

    function testFailMergeAndRemoveZeroAmounts() public {
        ReceivedItem[] memory receivedItemsA;
        ReceivedItem[] memory receivedItemsB;
        ReceivedItem[] memory receivedItemsC;
        (receivedItemsA, receivedItemsB, receivedItemsC) = getBenchArrays();

        ReceivedItem[] memory consideration = _mergeAndRemoveZeroAmounts(receivedItemsA, receivedItemsB, receivedItemsC);

        console.log(receivedItemsA[0].amount);
    }

    function getBenchArrays() internal returns (ReceivedItem[] memory, ReceivedItem[] memory, ReceivedItem[] memory) {
        ReceivedItem[] memory receivedItemsA = new ReceivedItem[](1);
        ReceivedItem[] memory receivedItemsB = new ReceivedItem[](1);
        ReceivedItem[] memory receivedItemsC = new ReceivedItem[](1);

        receivedItemsA[0] = ReceivedItem({
            itemType: ItemType.ERC20,
            token: address(2),
            identifier: 3,
            amount: 4,
            recipient: payable(address(0x45))
        });
        receivedItemsB[0] = ReceivedItem({
            itemType: ItemType.ERC721,
            token: address(2),
            identifier: 3,
            amount: 0,
            recipient: payable(address(1))
        });
        receivedItemsC[0] = ReceivedItem({
            itemType: ItemType.ERC20,
            token: address(2),
            identifier: 3,
            amount: 4,
            recipient: payable(address(0x69))
        });
        return (receivedItemsA, receivedItemsB, receivedItemsC);
    }

    function logConsideration(ReceivedItem[] memory consideration) public {
        for (uint256 i = 0; i < consideration.length; i++) {
            console.log("consideration[%s]", i);
            string memory key = "consideration";
            vm.serializeUint(key, "itemType", uint256(consideration[i].itemType));
            vm.serializeAddress(key, "token", consideration[i].token);
            vm.serializeUint(key, "identifier", consideration[i].identifier);
            vm.serializeUint(key, "amount", consideration[i].amount);
            console.log(vm.serializeAddress(key, "recipient", consideration[i].recipient));
        }
    }
}

contract TestRefConduitHelper is BaseTestConduitHelper, RefConduitHelper {
    function _mergeAndRemoveZeroAmounts(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsiderations
    ) internal pure override(BaseTestConduitHelper, RefConduitHelper) returns (ReceivedItem[] memory consideration) {
        return RefConduitHelper._mergeAndRemoveZeroAmounts(
            repayConsideration, carryConsideration, additionalConsiderations
        );
    }

    function _countNonZeroAmounts(ReceivedItem[] memory arr, uint256 validCount)
        internal
        pure
        override(BaseTestConduitHelper, RefConduitHelper)
        returns (uint256)
    {
        return RefConduitHelper._countNonZeroAmounts(arr, validCount);
    }
}

contract TestConduitHelper is BaseTestConduitHelper, ConduitHelper {
    function _mergeAndRemoveZeroAmounts(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsiderations
    ) internal pure override(BaseTestConduitHelper, ConduitHelper) returns (ReceivedItem[] memory consideration) {
        return
            ConduitHelper._mergeAndRemoveZeroAmounts(repayConsideration, carryConsideration, additionalConsiderations);
    }

    function _countNonZeroAmounts(ReceivedItem[] memory arr, uint256 validCount)
        internal
        pure
        override(BaseTestConduitHelper, ConduitHelper)
        returns (uint256)
    {
        return ConduitHelper._countNonZeroAmounts(arr, validCount);
    }
}
