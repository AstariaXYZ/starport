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
    mapping(address => mapping(bytes32 => bool)) usedSalts;

    function setUp() public {
        testContract = new TestContract();
    }

    function testValidateSaltRef(address user, bytes32 salt) public {
        StarPortLib.validateSaltRef(usedSalts, user, salt);

        assert(usedSalts[user][salt]);
        vm.expectRevert(abi.encodeWithSelector(StarPortLib.InvalidSalt.selector));

        StarPortLib.validateSaltRef(usedSalts, user, salt);
    }

    function testValidateSaltOpt(address user, bytes32 salt) public {
        StarPortLib.validateSalt(usedSalts, user, salt);

        assert(usedSalts[user][salt]);

        vm.expectRevert(abi.encodeWithSelector(StarPortLib.InvalidSalt.selector));
        StarPortLib.validateSalt(usedSalts, user, salt);
    }

    function testSpentToReceived() public {
        SpentItem[] memory spentItems = new SpentItem[](2);
        spentItems[0] = SpentItem({itemType: ItemType.ERC20, token: address(2), identifier: 3, amount: 4});

        spentItems[1] = SpentItem({itemType: ItemType.ERC20, token: address(2), identifier: 3, amount: 4});

        ReceivedItem[] memory consideration0 = testContract.spentToReceivedRef(spentItems, address(1));

        ReceivedItem[] memory consideration1 = testContract.spentToReceived(spentItems, address(1));

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

    function spentToReceived(SpentItem[] calldata spentItems, address recipient)
        external
        pure
        returns (ReceivedItem[] memory consideration)
    {
        return spentItems.toReceivedItems(recipient);
    }

    function spentToReceivedRef(SpentItem[] calldata spentItems, address recipient)
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
