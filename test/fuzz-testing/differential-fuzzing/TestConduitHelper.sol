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
import {Bound} from "starport-test/utils/Bound.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {Cast} from "starport-test/utils/Cast.sol";
import "starport-test/utils/FuzzStructs.sol" as Fuzz;

contract TestContract is ConduitHelper {
    function mergeConsiderations(ReceivedItem[] memory a, ReceivedItem[] memory b, ReceivedItem[] memory c)
        public
        pure
        returns (ReceivedItem[] memory)
    {
        return _mergeConsiderations(a, b, c);
    }
}

contract TestConduitHelper is Test, Bound, DeepEq {
    TestContract testContract = new TestContract();
    ReceivedItem[] receivedItems;

    using Cast for *;

    function testFuzzMergeConsiderations(
        Fuzz.ReceivedItem[] memory a,
        Fuzz.ReceivedItem[] memory b,
        Fuzz.ReceivedItem[] memory c
    ) public {
        ReceivedItem[] memory boundA = _boundReceivedItems(a);
        ReceivedItem[] memory boundB = _boundReceivedItems(b);
        ReceivedItem[] memory boundC = _boundReceivedItems(c);

        testContract.mergeConsiderations(boundA, boundB, boundC).toStorage(receivedItems);

        assertEq(receivedItems.length, a.length + b.length + c.length);
        for (uint256 i = boundC.length; i > 0; --i) {
            _deepEq(boundC[i - 1], receivedItems[receivedItems.length - 1]);
            receivedItems.pop();
        }
        for (uint256 i = boundB.length; i > 0; --i) {
            _deepEq(boundB[i - 1], receivedItems[receivedItems.length - 1]);
            receivedItems.pop();
        }

        for (uint256 i = boundA.length; i > 0; --i) {
            _deepEq(boundA[i - 1], receivedItems[receivedItems.length - 1]);
            receivedItems.pop();
        }
        assertEq(receivedItems.length, 0);
    }
}
