pragma solidity ^0.8.17;

import "forge-std/console2.sol";

import "./StarportTest.sol";

import {AstariaV1Pricing} from "starport-core/pricing/AstariaV1Pricing.sol";

import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {AstariaV1Status} from "starport-core/status/AstariaV1Status.sol";

import {BaseRecall} from "starport-core/status/BaseRecall.sol";

import {AstariaV1Settlement} from "starport-core/settlement/AstariaV1Settlement.sol";
import {AstariaV1LenderEnforcer} from "starport-core/enforcers/AstariaV1LenderEnforcer.sol";
import {BorrowerEnforcer} from "starport-core/enforcers/BorrowerEnforcer.sol";
// import "forge-std/console2.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";

contract AstariaV1Test is StarportTest {
    Account recaller;

    function setUp() public override {
        super.setUp();

        recaller = makeAndAllocateAccount("recaller");

        // erc20s[1].mint(recaller.addr, 10000);

        pricing = new AstariaV1Pricing(SP);
        settlement = new AstariaV1Settlement(SP);
        hook = new AstariaV1Status(SP);

        lenderEnforcer = new AstariaV1LenderEnforcer();

        vm.startPrank(recaller.addr);
        erc20s[0].approve(address(hook), 1e18);
        vm.stopPrank();

        // // 1% interest rate per second
        defaultPricingData = abi.encode(
            BasePricing.Details({carryRate: (uint256(1e16) * 10), rate: (uint256(1e16) * 150) / (365 * 1 days)})
        );

        // defaultSettlementData = new bytes(0);

        defaultStatusData = abi.encode(
            BaseRecall.Details({
                honeymoon: 1 days,
                recallWindow: 3 days,
                recallStakeDuration: 30 days,
                // 1000% APR
                recallMax: (uint256(1e16) * 1000) / (365 * 1 days),
                // 10%, 0.1
                recallerRewardRatio: uint256(1e16) * 10
            })
        );
    }

    function getRefinanceDetails(Starport.Loan memory loan, bytes memory pricingData, address transactor)
        public
        view
        returns (LenderEnforcer.Details memory)
    {
        (SpentItem[] memory considerationPayment, SpentItem[] memory carryPayment,) =
            Pricing(loan.terms.pricing).getRefinanceConsideration(loan, pricingData, transactor);

        loan = SP.applyRefinanceConsiderationToLoan(loan, considerationPayment, carryPayment, pricingData);
        loan.issuer = transactor;
        loan.start = 0;
        loan.originator = address(0);

        return LenderEnforcer.Details({loan: loan});
    }
}
