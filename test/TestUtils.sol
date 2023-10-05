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

contract TestStarLiteUtils is Test {
    TestContract testContract;

    function setUp() public {
        testContract = new TestContract();
    }

    function testSpentToReceived() public {
        SpentItem[] memory spentItems = new SpentItem[](2);
        spentItems[0] = SpentItem({itemType: ItemType.ERC20, token: address(2), identifier: 3, amount: 4});

        spentItems[1] = SpentItem({itemType: ItemType.ERC20, token: address(2), identifier: 3, amount: 4});

        ReceivedItem[] memory consideration0 = testContract.spentToReceivedBoring(spentItems, address(1));

        ReceivedItem[] memory consideration1 = testContract.spentToReceivedSexc(spentItems, address(1));

        assertEq(consideration0.length, consideration1.length);
        for (uint256 i = 0; i < consideration0.length; i++) {
            assert(consideration0[i].itemType == consideration1[i].itemType);
            assertEq(consideration0[i].token, consideration1[i].token);
            assertEq(consideration0[i].identifier, consideration1[i].identifier);
            assertEq(consideration0[i].amount, consideration1[i].amount);
            assertEq(consideration0[i].recipient, consideration1[i].recipient);
        }
    }

    function testEncodeReceivedWithRecipient() public {
        ReceivedItem[] memory receivedItems = new ReceivedItem[](2);
        receivedItems[0] = ReceivedItem({
            itemType: ItemType.ERC20,
            token: address(2),
            identifier: 3,
            amount: 4,
            recipient: payable(address(5))
        });

        receivedItems[1] = ReceivedItem({
            itemType: ItemType.ERC20,
            token: address(2),
            identifier: 3,
            amount: 4,
            recipient: payable(address(6))
        });

        ReceivedItem[] memory consideration0 =
            testContract.encodeReceivedItemsWithRecipientBoring(receivedItems, address(1));

        ReceivedItem[] memory consideration1 =
            testContract.encodeReceivedItemsWithRecipientSexc(receivedItems, address(1));

        assertEq(consideration0.length, consideration1.length);
        for (uint256 i = 0; i < consideration0.length; i++) {
            assert(consideration0[i].itemType == consideration1[i].itemType);
            assertEq(consideration0[i].token, consideration1[i].token);
            assertEq(consideration0[i].identifier, consideration1[i].identifier);
            assertEq(consideration0[i].amount, consideration1[i].amount);
            assertEq(consideration0[i].recipient, consideration1[i].recipient);
        }
    }
}

contract TestContract {
    using {StarPortLib.toReceivedItems} for SpentItem[];
    using {StarPortLib.encodeWithRecipient} for ReceivedItem[];

    function encodeReceivedItemsWithRecipientSexc(ReceivedItem[] calldata receivedItems, address recipient)
        external
        pure
        returns (ReceivedItem[] memory consideration)
    {
        return receivedItems.encodeWithRecipient(recipient);
    }

    function encodeReceivedItemsWithRecipientBoring(ReceivedItem[] calldata receivedItems, address recipient)
        external
        pure
        returns (ReceivedItem[] memory consideration)
    {
        consideration = new ReceivedItem[](receivedItems.length);
        for (uint256 i = 0; i < receivedItems.length;) {
            consideration[i] = ReceivedItem({
                itemType: receivedItems[i].itemType,
                token: receivedItems[i].token,
                identifier: receivedItems[i].identifier,
                amount: receivedItems[i].amount,
                recipient: payable(recipient)
            });
            unchecked {
                ++i;
            }
        }
    }

    function spentToReceivedSexc(SpentItem[] calldata spentItems, address recipient)
        external
        pure
        returns (ReceivedItem[] memory consideration)
    {
        return spentItems.toReceivedItems(recipient);
    }

    function spentToReceivedBoring(SpentItem[] calldata spentItems, address recipient)
        external
        pure
        returns (ReceivedItem[] memory consideration)
    {
        consideration = new ReceivedItem[](spentItems.length);
        for (uint256 i = 0; i < spentItems.length;) {
            consideration[i] = ReceivedItem({
                itemType: spentItems[i].itemType,
                token: spentItems[i].token,
                identifier: spentItems[i].identifier,
                amount: spentItems[i].amount,
                recipient: payable(recipient)
            });
            unchecked {
                ++i;
            }
        }
    }
}
