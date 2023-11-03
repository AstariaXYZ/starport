pragma solidity ^0.8.17;

import {ItemType, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {AdditionalTransfer} from "starport-core/lib/StarPortLib.sol";
import {TestBase} from "forge-std/Test.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {SettlementHandler} from "src/handlers/SettlementHandler.sol";
import {Pricing} from "src/pricing/Pricing.sol";

abstract contract MockCall is TestBase {
    function mockHookCall(address hook, bool status) public {
        vm.mockCall(hook, abi.encodeWithSelector(SettlementHook.isActive.selector), abi.encode(status));
    }

    function mockIsValidRefinanceCall(
        address pricing,
        SpentItem[] memory considerationPayment,
        SpentItem[] memory carryPayment,
        AdditionalTransfer[] memory additionalTransfers
    ) public {
        vm.mockCall(
            pricing,
            abi.encodeWithSelector(Pricing.isValidRefinance.selector),
            abi.encode(considerationPayment, carryPayment, additionalTransfers)
        );
    }

    function mockHandlerCall(address handler, ReceivedItem[] memory receivedItems, address authorized) public {
        vm.mockCall(
            handler,
            abi.encodeWithSelector(SettlementHandler.getSettlement.selector),
            abi.encode(receivedItems, authorized)
        );
    }

    function mockHandlerExecuteFail(address handler) public {
        vm.mockCall(handler, abi.encodeWithSelector(SettlementHandler.execute.selector), abi.encode(bytes4(0)));
    }
}
