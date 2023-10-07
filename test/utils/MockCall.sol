import {ItemType, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {TestBase} from "forge-std/Test.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {SettlementHandler} from "src/handlers/SettlementHandler.sol";

abstract contract MockCall is TestBase {

    function mockHookCall(address hook, bool status) public {
        vm.mockCall(hook, abi.encodeWithSelector(SettlementHook.isActive.selector), abi.encode(status));
    }

    function mockHandlerCall(address handler, ReceivedItem[] memory receivedItems, address authorized) public {
        vm.mockCall(
            handler,
            abi.encodeWithSelector(SettlementHandler.getSettlement.selector),
            abi.encode(receivedItems, authorized)
        );
    }
}
