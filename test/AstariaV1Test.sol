pragma solidity =0.8.17;

import "forge-std/console2.sol";

import "./StarPortTest.sol";

import {AstariaV1Pricing} from "starport-core/pricing/AstariaV1Pricing.sol";

import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {AstariaV1SettlementHook} from "starport-core/hooks/AstariaV1SettlementHook.sol";

import {BaseRecall} from "starport-core/hooks/BaseRecall.sol";

import {AstariaV1SettlementHandler} from "starport-core/handlers/AstariaV1SettlementHandler.sol";
import {BaseEnforcer} from "starport-core/BaseEnforcer.sol";
// import "forge-std/console2.sol";

contract AstariaV1Test is StarPortTest {
    Account recaller;
    address recallerConduit;
    bytes32 conduitKeyRecaller;

    BorrowerEnforcer borrowerEnforcer;
    LenderEnforcer lenderEnforcer;

    function setUp() public override {
        super.setUp();

        recaller = makeAndAllocateAccount("recaller");

        // erc20s[1].mint(recaller.addr, 10000);

        pricing = new AstariaV1Pricing(LM);
        handler = new AstariaV1SettlementHandler(LM);
        hook = new AstariaV1SettlementHook(LM);

        borrowerEnforcer = new BorrowerEnforcer();
        lenderEnforcer = new LenderEnforcer();
        vm.label(address(borrowerEnforcer), "BorrowerEnforcer");
        vm.label(address(lenderEnforcer), "LenderEnforcer");

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

    function getLenderSignedCaveat(BaseEnforcer.Details memory details, Account memory signer, bytes32 salt, address enforcer) public pure returns(Enforcer.Caveat memory caveat) {
        caveat = Enforcer.Caveat({
            enforcer: enforcer,
            salt: salt,
            caveat: abi.encode(details),
            approval: Enforcer.Approval({
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        });

        (caveat.approval.v, caveat.approval.r, caveat.approval.s) = vm.sign(signer.key, keccak256(abi.encode(caveat.enforcer, caveat.caveat, caveat.salt)));
    }

    function getRefinanceDetails(LoanManager.Loan memory loan, bytes memory pricingData, address transactor) public view returns(BaseEnforcer.Details memory) {
        (
            SpentItem[] memory considerationPayment,
            SpentItem[] memory carryPayment,
            ConduitTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).isValidRefinance(loan, pricingData, transactor);

        loan = LM.applyRefinanceConsiderationToLoan(loan, considerationPayment, carryPayment, pricingData);
        loan.issuer = transactor;
        loan.start = 0;
        loan.originator = address(0);
        
        return BaseEnforcer.Details({
            loan: loan
        });
    }
}
