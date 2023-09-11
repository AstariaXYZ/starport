pragma solidity =0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {StarPortTest} from "./StarPortTest.sol";

import {AstariaV1Pricing} from "src/pricing/AstariaV1Pricing.sol";
import {AstariaV1SettlementHook} from "src/hooks/AstariaV1SettlementHook.sol";

import {BaseRecall} from "src/hooks/BaseRecall.sol";

import {AstariaV1SettlementHandler} from "src/handlers/AstariaV1SettlementHandler.sol";

contract AstariaV1Test is StarPortTest {

  function setUp() public override {
    console.log("woof");
    super.setUp();

    // // 1% interest rate per second
    // bytes defaultPricingData =
    //   abi.encode(
    //     BasePricing.Details({
    //       carryRate: (uint256(1e16) * 10),
    //       rate: (uint256(1e16) * 150) / (365 * 1 days)
    //     })
    //   );

    defaultHandlerData = new bytes(0);

    defaultHookData =
      abi.encode(
        BaseRecall.Details({
          honeymoon: 1 days,
          recallWindow: 3 days,
          recallStakeDuration: 30 days,
          // 1000% APR
          recallMax: (uint256(1e16) * 1000) / (365 * 1 days)
        })
      );
      

    pricing = new AstariaV1Pricing(LM);
    console.log("pricing", address(pricing));
    handler = new AstariaV1SettlementHandler(LM);
    hook = new AstariaV1SettlementHook();
  }

}