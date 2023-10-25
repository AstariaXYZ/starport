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
import {RefStarPortLib} from "starport-core/lib/RefStarPortLib.sol";
import "starport-test/utils/FuzzStructs.sol" as Fuzz;
import {Bound} from "starport-test/utils/Bound.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";

contract DiffFuzzTestStarPortLib is Test, Bound, DeepEq {
    StarPortLibImpl testContract;
    RefStarPortLibImpl refContract;

    function setUp() public {
        testContract = new StarPortLibImpl();
        refContract = new RefStarPortLibImpl();
    }

    function testSpentToReceived(Fuzz.SpentItem[] memory unbSpentItems) public view {
        SpentItem[] memory spentItems = _boundSpentItems(unbSpentItems);

        ReceivedItem[] memory consideration0 = testContract.toReceivedItems(spentItems, address(1));
        ReceivedItem[] memory consideration1 = refContract.toReceivedItems(spentItems, address(1));

        _deepEq(consideration0, consideration1);
    }

    function testUnboundSpentToReceived(Fuzz.SpentItem[] memory unbSpentItems) public {
        console.log("testUnboundSpentToReceived");
        (bool success,) = address(refContract).call(
            abi.encodeWithSelector(RefStarPortLibImpl.toReceivedItems.selector, unbSpentItems, address(1))
        );
        bool expectRevert = !success;

        (success,) = address(testContract).call(
            abi.encodeWithSelector(StarPortLibImpl.toReceivedItems.selector, unbSpentItems, address(1))
        );
        if (expectRevert) {
            assertTrue(!success, "expected revert");
        } else {
            assertTrue(success, "expected success");
        }
    }

}

abstract contract BaseTestStarPortLib is Test {
    StarPortLibImpl testContract;

    function _setUp(address testImpl) internal {
        testContract = StarPortLibImpl(testImpl);
    }

    function testValidateSalt(address user, bytes32 salt) public {
        testContract.validateSalt(user, salt);

        assert(testContract.usedSalts(user, salt));

        vm.expectRevert(abi.encodeWithSelector(StarPortLib.InvalidSalt.selector));
        testContract.validateSalt(user, salt);
    }

    function testSpentToReceived() public {
        SpentItem[] memory spentItems = new SpentItem[](2);
        spentItems[0] = SpentItem({itemType: ItemType.ERC20, token: address(2), identifier: 3, amount: 4});

        spentItems[1] = SpentItem({itemType: ItemType.ERC20, token: address(2), identifier: 3, amount: 4});

        address recipient = address(1);
        ReceivedItem[] memory consideration0 = testContract.toReceivedItems(spentItems, recipient);

        assertEq(consideration0.length, spentItems.length);
        for (uint256 i = 0; i < consideration0.length; i++) {
            assert(consideration0[i].itemType == spentItems[i].itemType);
            assertEq(consideration0[i].token, spentItems[i].token);
            assertEq(consideration0[i].identifier, spentItems[i].identifier);
            assertEq(consideration0[i].amount, spentItems[i].amount);
            assertEq(consideration0[i].recipient, recipient);
        }
    }
}

contract TestStarPortLib is BaseTestStarPortLib {
    function setUp() public {
        _setUp(address(new StarPortLibImpl()));
    }
}

contract TestRefStarPortLib is BaseTestStarPortLib {
    function setUp() public {
        _setUp(address(new RefStarPortLibImpl()));
    }
}

contract StarPortLibImpl {
    using RefStarPortLib for *;

    mapping(address => mapping(bytes32 => bool)) public usedSalts;

    function toReceivedItems(SpentItem[] calldata spentItems, address recipient)
        external
        pure
        returns (ReceivedItem[] memory consideration)
    {
        return spentItems.toReceivedItems(recipient);
    }

    function validateSalt(address user, bytes32 salt) external {
        usedSalts.validateSalt(user, salt);
    }
}

contract RefStarPortLibImpl {
    using RefStarPortLib for *;

    mapping(address => mapping(bytes32 => bool)) public usedSalts;

    function toReceivedItems(SpentItem[] calldata spentItems, address recipient)
        external
        pure
        returns (ReceivedItem[] memory consideration)
    {
        return spentItems.toReceivedItems(recipient);
    }

    function validateSalt(address user, bytes32 salt) external {
        usedSalts.validateSalt(user, salt);
    }
}
