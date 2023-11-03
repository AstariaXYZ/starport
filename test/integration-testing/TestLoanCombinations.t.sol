pragma solidity ^0.8.17;

import "starport-test/StarPortTest.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";

import {StarPortLib} from "starport-core/lib/StarPortLib.sol";

import "forge-std/console.sol";

contract TestLoanCombinations is StarPortTest {
    using {StarPortLib.getId} for Starport.Loan;
    // TODO test liquidations

    function testLoan721for20SimpleInterestDutchFixedRepay() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermHook),
            settlement: address(dutchAuctionHandler),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
        assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

        uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});

        assertTrue(erc721s[0].balanceOf(borrower.addr) < initial721Balance, "Borrower ERC721 was not sent out");
        assertTrue(erc20s[0].balanceOf(borrower.addr) > initial20Balance, "Borrower did not receive ERC20");

        uint256 loanId = loan.getId();
        assertTrue(SP.active(loanId), "LoanId not in active state after a new loan");
        skip(10 days);

        _repayLoan({borrower: borrower.addr, amount: 375, loan: loan});
    }

    function testLoan20for20SimpleInterestDutchFixedRepay() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermHook),
            settlement: address(dutchAuctionHandler),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan = _createLoan20Collateral20Debt({
            lender: lender.addr,
            collateralAmount: 20, // erc20s[1]
            borrowAmount: 100, // erc20s[0]
            terms: terms
        });

        skip(10 days);

        _repayLoan({borrower: borrower.addr, amount: 375, loan: loan});
    }

    function testLoan20For721SimpleInterestDutchFixedRepay() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermHook),
            settlement: address(dutchAuctionHandler),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan = _createLoan20Collateral721Debt({lender: lender.addr, terms: terms});
        skip(10 days);

        _repayLoan({ // TODO different repay
            borrower: borrower.addr,
            amount: 375,
            loan: loan
        });
    }

    function testLoanAstariaSettlementRepay() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermHook),
            settlement: address(dutchAuctionHandler),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});
        skip(10 days);

        _repayLoan({borrower: borrower.addr, amount: 375, loan: loan});
    }

    function testLoanSimpleInterestEnglishFixed() public {
        uint256[] memory reservePrice = new uint256[](1);
        reservePrice[0] = 300;
        bytes memory englishAuctionsettlementData =
            abi.encode(EnglishAuctionHandler.Details({reservePrice: reservePrice, window: 7 days}));

        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermHook),
            settlement: address(englishAuctionHandler),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: englishAuctionsettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});
        skip(10 days);

        _repayLoan({borrower: borrower.addr, amount: 375, loan: loan});
    }
}
