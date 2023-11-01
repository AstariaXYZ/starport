pragma solidity ^0.8.17;

import "starport-test/AstariaV1Test.sol";
import {StarPortLib, Actions} from "starport-core/lib/StarPortLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import "forge-std/console2.sol";

contract TestStrategistOriginator is AstariaV1Test, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;

    using {StarPortLib.getId} for LoanManager.Loan;
    // recaller is not the lender, liquidation amount is a dutch auction

    function testGetSettlementFailedDutchAuction() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();
        //
        //        uint256 stake;
        //        {
        //            uint256 balanceBefore = erc20s[0].balanceOf(recaller.addr);
        //            uint256 recallContractBalanceBefore = erc20s[0].balanceOf(address(hook));
        //            BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
        //            vm.warp(block.timestamp + details.honeymoon);
        //            vm.startPrank(recaller.addr);
        //
        //            BaseRecall recallContract = BaseRecall(address(hook));
        //            recallContract.recall(loan, recallerConduit);
        //            vm.stopPrank();
        //
        //            uint256 balanceAfter = erc20s[0].balanceOf(recaller.addr);
        //            uint256 recallContractBalanceAfter = erc20s[0].balanceOf(address(hook));
        //
        //            BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        //            stake = BasePricing(address(pricing)).calculateInterest(
        //                details.recallStakeDuration, loan.debt[0].amount, pricingDetails.rate
        //            );
        //            assertEq(balanceBefore, balanceAfter + stake, "Recaller balance not transfered correctly");
        //            assertEq(
        //                recallContractBalanceBefore + stake,
        //                recallContractBalanceAfter,
        //                "Balance not transfered to recall contract correctly"
        //            );
        //        }

        bytes4 recallsSelector = bytes4(keccak256("recalls(uint256)"));
        vm.mockCall(
            address(loan.terms.hook), abi.encodeWithSelector(recallsSelector, loanId), abi.encode(address(0), uint64(2))
        );
        uint256 auctionStart = AstariaV1SettlementHandler(loan.terms.handler).getAuctionStart(loan);
        DutchAuctionHandler.Details memory details = abi.decode(loan.terms.handlerData, (DutchAuctionHandler.Details));

        vm.warp(auctionStart + details.window + 5);
        (ReceivedItem[] memory settlementConsideration, address restricted) =
            SettlementHandler(loan.terms.handler).getSettlement(loan);
        assertEq(settlementConsideration.length, 0, "Settlement consideration should be empty");
        assertEq(restricted, address(loan.issuer), "Restricted address should be loan.issuer");
    }
}
