pragma solidity =0.8.17;

import "forge-std/Script.sol";
import "../LoanManager.sol";
import "../originators/UniqueOriginator.sol";
import "../pricing/FixedTermPricing.sol";
import "../handlers/EnglishAuctionHandler.sol";
import "../hooks/FixedTermHook.sol";

contract Deploy is Script {
  function run() public {
    vm.startBroadcast();
    LoanManager LM = new LoanManager();
    UniqueOriginator UO = new UniqueOriginator(LM, msg.sender, 0);
    Pricing PR = new FixedTermPricing(LM);
    address EAZone = address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
    SettlementHandler SH = new EnglishAuctionHandler(
      LM,
      ConsiderationInterface(LM.seaport()),
      EAZone
    );
    SettlementHook HK = new FixedTermHook();
    vm.stopBroadcast();
  }
}
