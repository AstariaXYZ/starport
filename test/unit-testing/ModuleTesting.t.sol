pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Validation} from "starport-core/lib/Validation.sol";
import "forge-std/console.sol";
import "../utils/DeepEq.sol";

contract ModuleTesting is StarportTest, DeepEq {
    using FixedPointMathLib for uint256;
    using LibString for string;

    function testFixedTermDutchAuctionSettlement() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});
        FixedTermStatus.Details memory details = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));

        uint256 expectedAuctionStart = block.timestamp + details.loanDuration;

        assertEq(
            expectedAuctionStart,
            FixedTermDutchAuctionSettlement(loan.terms.settlement).getAuctionStart(loan),
            "Auction start time is not correct"
        );
    }

    function testFixedTermDutchAuctionSettlementNotValid() public {
        DutchAuctionSettlement.Details memory details =
            DutchAuctionSettlement.Details({startingPrice: 1 ether, endingPrice: 10 ether, window: 7 days});
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: abi.encode(details),
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});

        assertEq(
            FixedTermDutchAuctionSettlement(loan.terms.settlement).validate(loan), bytes4(0xFFFFFFFF), "Loan is valid"
        );
    }

    function testFixedTermDutchAuctionSettlementValid() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});

        assertEq(
            FixedTermDutchAuctionSettlement(loan.terms.settlement).validate(loan),
            Validation.validate.selector,
            "Loan is invalid"
        );
    }

    function testFixedTermDutchAuctionSettlementGetSettlementAuctionExpired() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});
        FixedTermStatus.Details memory details = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));

        DutchAuctionSettlement.Details memory dutchAuctionDetails =
            abi.decode(loan.terms.settlementData, (DutchAuctionSettlement.Details));
        skip(details.loanDuration + dutchAuctionDetails.window + 1);
        (ReceivedItem[] memory settlementConsideration, address authorized) =
            FixedTermDutchAuctionSettlement(loan.terms.settlement).getSettlementConsideration(loan);
        _deepEq(settlementConsideration, new ReceivedItem[](0));
        assertEq(authorized, loan.issuer, "Authorized is not correct");
    }
}
