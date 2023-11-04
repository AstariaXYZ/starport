pragma solidity ^0.8.17;

import "starport-test/AstariaV1Test.sol";
import {StarportLib, Actions} from "starport-core/lib/StarportLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import "forge-std/console2.sol";

contract TestAstariaV1Settlement is AstariaV1Test, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;

    using {StarportLib.getId} for Starport.Loan;
    // recaller is not the lender, liquidation amount is a dutch auction

    function testGetSettlementFailedDutchAuction() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();

        bytes4 recallsSelector = bytes4(keccak256("recalls(uint256)"));
        vm.mockCall(
            address(loan.terms.status),
            abi.encodeWithSelector(recallsSelector, loanId),
            abi.encode(address(this), uint64(2))
        );
        uint256 auctionStart = AstariaV1Settlement(loan.terms.settlement).getAuctionStart(loan);
        DutchAuctionSettlement.Details memory details =
            abi.decode(loan.terms.settlementData, (DutchAuctionSettlement.Details));

        vm.warp(auctionStart + details.window + 5);
        (ReceivedItem[] memory settlementConsideration, address restricted) =
            Settlement(loan.terms.settlement).getSettlement(loan);
        assertEq(settlementConsideration.length, 0, "Settlement consideration should be empty");
        assertEq(restricted, address(loan.issuer), "Restricted address should be loan.issuer");
    }

    function testGetSettlementLoanNotRecalled() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();

        vm.expectRevert(abi.encodeWithSelector(AstariaV1Settlement.LoanNotRecalled.selector));
        Settlement(loan.terms.settlement).getSettlement(loan);
    }

    function testGetSettlementDutchAuctionSettlementAbove() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();

        bytes4 recallsSelector = bytes4(keccak256("recalls(uint256)"));
        vm.mockCall(
            address(loan.terms.status),
            abi.encodeWithSelector(recallsSelector, loanId),
            abi.encode(address(this), uint64(2))
        );

        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));

        vm.warp(AstariaV1Settlement(loan.terms.settlement).getAuctionStart(loan));
        skip(7 days - 1300);
        uint256 currentAuctionPrice = AstariaV1Settlement(loan.terms.settlement).getCurrentAuctionPrice(loan);

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
            Settlement(loan.terms.settlement).getSettlement(loan);
        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        assertEq(settlementConsideration[0].amount, carry, "Settlement 0 (originator payment) incorrect");
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
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});

        vm.expectRevert(abi.encodeWithSelector(AstariaV1Settlement.LoanNotRecalled.selector));
        AstariaV1Settlement(loan.terms.settlement).getAuctionStart(loan);
    }

    function testGetAuctionStart() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();

        bytes4 recallsSelector = bytes4(keccak256("recalls(uint256)"));
        uint256 recallStart = uint256(2);
        vm.mockCall(
            address(loan.terms.status),
            abi.encodeWithSelector(recallsSelector, loanId),
            abi.encode(address(this), recallStart)
        );

        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));
        uint256 auctionStart = recallStart + details.recallWindow + 1;

        assertEq(
            auctionStart, AstariaV1Settlement(loan.terms.settlement).getAuctionStart(loan), "start times dont match"
        );
    }

    function testGetCurrentAuctionPrice() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();

        bytes4 recallsSelector = bytes4(keccak256("recalls(uint256)"));
        vm.mockCall(
            address(loan.terms.status),
            abi.encodeWithSelector(recallsSelector, loanId),
            abi.encode(address(this), uint64(2))
        );

        DutchAuctionSettlement.Details memory handlerDetails =
            abi.decode(loan.terms.settlementData, (DutchAuctionSettlement.Details));

        vm.warp(AstariaV1Settlement(loan.terms.settlement).getAuctionStart(loan));
        skip(7 days);
        uint256 currentAuctionPrice = AstariaV1Settlement(loan.terms.settlement).getCurrentAuctionPrice(loan);

        assertEq(currentAuctionPrice, handlerDetails.endingPrice);
    }

    function testGetCurrentAuctionPriceNoAuction() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();

        vm.expectRevert(abi.encodeWithSelector(AstariaV1Settlement.NoAuction.selector));
        uint256 currentAuctionPrice = AstariaV1Settlement(loan.terms.settlement).getCurrentAuctionPrice(loan);
    }

    //    function testV1SettlementHandlerExecute() public {
    //        Starport.Terms memory terms = Starport.Terms({
    //            status: address(hook),
    //            settlement: address(settlement),
    //            pricing: address(pricing),
    //            pricingData: defaultPricingData,
    //            settlementData: defaultSettlementData,
    //            statusData: defaultStatusData
    //        });
    //        Starport.Loan memory loan =
    //            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
    //
    //        vm.expectRevert(abi.encodeWithSelector(AstariaV1Settlement.ExecuteHandlerNotImplemented.selector));
    //        AstariaV1Settlement(loan.terms.settlement).postSettlement(loan, address(this));
    //    }

    function testV1SettlementHandlerValidate() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});

        assert(AstariaV1Settlement(loan.terms.settlement).validate(loan));
    }

    function testV1SettlementHandlerValidateInvalidHandler() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});

        address settlement = loan.terms.settlement;
        loan.terms.settlement = address(0);
        vm.expectRevert(abi.encodeWithSelector(AstariaV1Settlement.InvalidHandler.selector));
        AstariaV1Settlement(settlement).validate(loan);
    }
}
