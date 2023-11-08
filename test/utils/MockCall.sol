pragma solidity ^0.8.17;

import {ItemType, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";
import {TestBase} from "forge-std/Test.sol";
import {Status} from "src/status/Status.sol";
import {Settlement} from "src/settlement/Settlement.sol";
import {Pricing} from "src/pricing/Pricing.sol";

abstract contract MockCall is TestBase {
    function mockStatusCall(address hook, bool status) public {
        vm.mockCall(hook, abi.encodeWithSelector(Status.isActive.selector), abi.encode(status));
    }

    function mockIsValidRefinanceCall(
        address pricing,
        SpentItem[] memory considerationPayment,
        SpentItem[] memory carryPayment,
        AdditionalTransfer[] memory additionalTransfers
    ) public {
        vm.mockCall(
            pricing,
            abi.encodeWithSelector(Pricing.getRefinanceConsideration.selector),
            abi.encode(considerationPayment, carryPayment, additionalTransfers)
        );
    }

    function mockSettlementCall(address settlement, ReceivedItem[] memory receivedItems, address authorized) public {
        vm.mockCall(
            settlement,
            abi.encodeWithSelector(Settlement.getSettlementConsideration.selector),
            abi.encode(receivedItems, authorized)
        );
    }

    function mockPostSettlementFail(address settlement) public {
        vm.mockCall(settlement, abi.encodeWithSelector(Settlement.postSettlement.selector), abi.encode(bytes4(0)));
    }

    function mockPostRepaymentFail(address settlement) public {
        vm.mockCall(settlement, abi.encodeWithSelector(Settlement.postRepayment.selector), abi.encode(bytes4(0)));
    }
}
