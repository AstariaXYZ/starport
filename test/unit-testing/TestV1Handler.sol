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

    function testGetSettlementDutchAuctionSettlementAbove() public {
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

        bytes4 recallsSelector = bytes4(keccak256("recalls(uint256)"));
        vm.mockCall(
            address(loan.terms.hook),
            abi.encodeWithSelector(recallsSelector, loanId),
            abi.encode(address(this), uint64(2))
        );

        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));

        vm.warp(AstariaV1SettlementHandler(loan.terms.handler).getAuctionStart(loan));
        skip(7 days - 1300);
        uint256 currentAuctionPrice = AstariaV1SettlementHandler(loan.terms.handler).getCurrentAuctionPrice(loan);

        vm.mockCall(
            loan.terms.pricing,
            abi.encodeWithSelector(
                BasePricing.getInterest.selector, loan, pricingDetails.rate, loan.start, block.timestamp, 0
            ),
            abi.encode(currentAuctionPrice - loan.debt[0].amount + 1)
        );

        uint256 interest =
            BasePricing(loan.terms.pricing).getInterest(loan, pricingDetails.rate, loan.start, block.timestamp, 0);
        uint256 carry = interest.mulWad(pricingDetails.carryRate);
        (ReceivedItem[] memory settlementConsideration, address restricted) =
            SettlementHandler(loan.terms.handler).getSettlement(loan);
        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.hookData, (BaseRecall.Details));

        assertEq(
            settlementConsideration[0].amount,
            currentAuctionPrice - loan.debt[0].amount + interest - carry,
            "Settlement 0 (originator payment) incorrect"
        );
        assertEq(
            settlementConsideration[1].amount,
            (currentAuctionPrice - settlementConsideration[0].amount).mulWad(hookDetails.recallerRewardRatio),
            "Settlement 1 (recaller reward) incorrect"
        );
        assertEq(
            settlementConsideration[2].amount,
            currentAuctionPrice - settlementConsideration[0].amount - settlementConsideration[1].amount,
            "Settlement 2 (issuer payment) incorrect"
        );
        assertEq(settlementConsideration.length, 3, "Settlement consideration should have 3 elements");
        assertEq(restricted, address(0), "Restricted address should be address(0)");
    }

    function testGetAuctionStartNotStarted() public {
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

        vm.expectRevert(abi.encodeWithSelector(AstariaV1SettlementHandler.AuctionNotStarted.selector));
        AstariaV1SettlementHandler(loan.terms.handler).getAuctionStart(loan);
    }

    function testGetAuctionStart() public {
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

        bytes4 recallsSelector = bytes4(keccak256("recalls(uint256)"));
        uint256 recallStart = uint256(2);
        vm.mockCall(
            address(loan.terms.hook),
            abi.encodeWithSelector(recallsSelector, loanId),
            abi.encode(address(this), recallStart)
        );

        BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
        uint256 auctionStart = recallStart + details.recallWindow + 1;

        assertEq(
            auctionStart, AstariaV1SettlementHandler(loan.terms.handler).getAuctionStart(loan), "start times dont match"
        );
    }

    function testV1SettlementHandlerExecute() public {
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

        vm.expectRevert(abi.encodeWithSelector(AstariaV1SettlementHandler.ExecuteHandlerNotImplemented.selector));
        AstariaV1SettlementHandler(loan.terms.handler).execute(loan, address(this));
    }

    function testV1SettlementHandlerValidate() public {
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

        assert(AstariaV1SettlementHandler(loan.terms.handler).validate(loan));
    }

    function testV1SettlementHandlerValidateInvalidHandler() public {
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

        address handler = loan.terms.handler;
        loan.terms.handler = address(0);
        vm.expectRevert(abi.encodeWithSelector(AstariaV1SettlementHandler.InvalidHandler.selector));
        AstariaV1SettlementHandler(handler).validate(loan);
    }
}
