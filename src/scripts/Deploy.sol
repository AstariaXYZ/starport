//pragma solidity ^0.8.17;;
//
//import "forge-std/Script.sol";
//import "../Starport.sol";
//import "../originators/UniqueOriginator.sol";
//import "../pricing/SimpleInterestPricing.sol";
//import "../settlement/EnglishAuctionHandler.sol";
//import "../status/FixedTermStatus.sol";
//
//contract Deploy is Script {
//    function run() public {
//        vm.startBroadcast();
//        Starport SP = new Starport();
//        UniqueOriginator UO = new UniqueOriginator(SP, msg.sender, 0);
//        Pricing PR = new SimpleInterestPricing(SP);
//        address EAZone = address(0x004C00500000aD104D7DBd00e3ae0A5C00560C00);
//        SettlementHandler SH = new EnglishAuctionHandler(
//      SP,
//      ConsiderationInterface(SP.seaport()),
//      EAZone
//    );
//        FixedTermStatus HK = new FixedTermStatus();
//        vm.stopBroadcast();
//    }
//}
