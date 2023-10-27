pragma solidity =0.8.17;

import "forge-std/console2.sol";

import "./StarPortTest.sol";

import {AstariaV1Pricing} from "starport-core/pricing/AstariaV1Pricing.sol";

import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {AstariaV1SettlementHook} from "starport-core/hooks/AstariaV1SettlementHook.sol";

import {BaseRecall} from "starport-core/hooks/BaseRecall.sol";

import {AstariaV1SettlementHandler} from "starport-core/handlers/AstariaV1SettlementHandler.sol";
import {LenderEnforcer} from "starport-core/enforcers/LenderEnforcer.sol";
import {BorrowerEnforcer} from "starport-core/enforcers/BorrowerEnforcer.sol";
// import "forge-std/console2.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";

contract AstariaV1Test is StarPortTest {
    Account recaller;
    address recallerConduit;
    bytes32 conduitKeyRecaller;

    function setUp() public override {
        super.setUp();

        recaller = makeAndAllocateAccount("recaller");

        // erc20s[1].mint(recaller.addr, 10000);

        pricing = new AstariaV1Pricing(LM);
        handler = new AstariaV1SettlementHandler(LM);
        hook = new AstariaV1SettlementHook(LM);

        conduitKeyRecaller = bytes32(uint256(uint160(address(recaller.addr))) << 96);

        vm.startPrank(recaller.addr);
        recallerConduit = conduitController.createConduit(conduitKeyRecaller, recaller.addr);
        conduitController.updateChannel(recallerConduit, address(hook), true);
        erc20s[0].approve(address(recallerConduit), 1e18);
        vm.stopPrank();

        // // 1% interest rate per second
        defaultPricingData = abi.encode(
            BasePricing.Details({carryRate: (uint256(1e16) * 10), rate: (uint256(1e16) * 150) / (365 * 1 days)})
        );

        // defaultHandlerData = new bytes(0);

        defaultHookData = abi.encode(
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

    function getLenderSignedCaveat(LenderEnforcer.Details memory details, Account memory signer, bytes32 salt, address enforcer) public view returns(CaveatEnforcer.CaveatWithApproval memory caveatApproval) {
         caveatApproval.caveat = CaveatEnforcer.Caveat({
            enforcer: enforcer,
            salt: salt,
            deadline: block.timestamp + 1 days,
            data: abi.encode(details)
        });

        bytes32 hash = LM.hashCaveatWithSaltAndNonce(signer.addr, caveatApproval.caveat);
        
        (caveatApproval.v, caveatApproval.r, caveatApproval.s) = vm.sign(signer.key, hash);
    }

    function getRefinanceDetails(LoanManager.Loan memory loan, bytes memory pricingData, address transactor) public view returns(LenderEnforcer.Details memory) {
        (
            SpentItem[] memory considerationPayment,
            SpentItem[] memory carryPayment,
        ) = Pricing(loan.terms.pricing).isValidRefinance(loan, pricingData, transactor);

        loan = LM.applyRefinanceConsiderationToLoan(loan, considerationPayment, carryPayment, pricingData);
        loan.issuer = transactor;
        loan.start = 0;
        loan.originator = address(0);
        
        return LenderEnforcer.Details({
            loan: loan
        });
    }
}
