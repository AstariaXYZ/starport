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
import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {RefStarportLib} from "starport-test/fuzz-testing/differential-fuzzing/RefStarportLib.sol";
import "starport-test/utils/FuzzStructs.sol" as Fuzz;
import {Bound} from "starport-test/utils/Bound.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";

contract DiffFuzzTestStarportLib is Test, Bound, DeepEq {
    StarportLibImpl testContract;
    RefStarportLibImpl refContract;

    function setUp() public {
        testContract = new StarportLibImpl();
        refContract = new RefStarportLibImpl();
    }

    function _boundTokenByItemType(ItemType itemType) internal view override returns (address token) {
        token = _toAddress(_boundMin(100, 1000));
    }
}

abstract contract BaseTestStarportLib is Test {
    StarportLibImplAbstract testContract;

    function _setUp(address testImpl) internal {
        testContract = StarportLibImplAbstract(testImpl);
    }

    function testValidateSalt(address user, bytes32 salt) public {
        vm.assume(salt != bytes32(0));
        testContract.validateSalt(user, salt);

        assert(testContract.usedSalts(user, salt));

        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidSalt.selector));
        testContract.validateSalt(user, salt);
    }
}

contract TestStarportLib is BaseTestStarportLib {
    function setUp() public {
        _setUp(address(new StarportLibImpl()));
    }
}

contract TestRefStarportLib is BaseTestStarportLib {
    function setUp() public {
        _setUp(address(new RefStarportLibImpl()));
    }
}

abstract contract StarportLibImplAbstract {
    mapping(address => mapping(bytes32 => bool)) public usedSalts;

    function validateSalt(address user, bytes32 salt) external virtual;
}

contract StarportLibImpl is StarportLibImplAbstract {
    using StarportLib for *;

    function validateSalt(address user, bytes32 salt) external override {
        //        usedSalts.validateSalt(user, salt);
        StarportLib.validateSalt(usedSalts, user, salt);
    }
}

contract RefStarportLibImpl is StarportLibImplAbstract {
    using RefStarportLib for *;

    function validateSalt(address user, bytes32 salt) external override {
        //        usedSalts.validateSalt(user, salt);
        RefStarportLib.validateSalt(usedSalts, user, salt);
    }
}
