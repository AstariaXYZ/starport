// SPDX-License-Identifier: BUSL-1.1
//
//                       ↑↑↑↑                 ↑↑
//                       ↑↑↑↑                ↑↑↑↑↑
//                       ↑↑↑↑              ↑   ↑
//                       ↑↑↑↑            ↑↑↑↑↑
//            ↑          ↑↑↑↑          ↑   ↑
//          ↑↑↑↑↑        ↑↑↑↑        ↑↑↑↑↑
//            ↑↑↑↑↑      ↑↑↑↑      ↑↑↑↑↑                                   ↑↑↑                                                                      ↑↑↑
//              ↑↑↑↑↑    ↑↑↑↑    ↑↑↑↑↑                          ↑↑↑        ↑↑↑         ↑↑↑            ↑↑         ↑↑            ↑↑↑            ↑↑    ↑↑↑
//                ↑↑↑↑↑  ↑↑↑↑  ↑↑↑↑↑                         ↑↑↑↑ ↑↑↑↑   ↑↑↑↑↑↑↑    ↑↑↑↑↑↑↑↑↑     ↑↑ ↑↑↑   ↑↑↑↑↑↑↑↑↑↑↑     ↑↑↑↑↑↑↑↑↑↑    ↑↑↑ ↑↑↑  ↑↑↑↑↑↑↑
//                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑                           ↑↑     ↑↑↑    ↑↑↑     ↑↑↑     ↑↑↑    ↑↑↑      ↑↑↑      ↑↑↑   ↑↑↑      ↑↑↑   ↑↑↑↑       ↑↑↑
//                    ↑↑↑↑↑↑↑↑↑↑                             ↑↑↑↑↑         ↑↑↑            ↑↑↑↑    ↑↑       ↑↑↑       ↑↑   ↑↑↑       ↑↑↑  ↑↑↑        ↑↑↑
//  ↑↑↑↑  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑   ↑↑↑   ↑↑↑             ↑↑↑↑↑↑↑    ↑↑↑     ↑↑↑↑↑↑  ↑↑↑    ↑↑       ↑↑↑       ↑↑↑  ↑↑↑       ↑↑↑  ↑↑↑        ↑↑↑
//  ↑↑↑↑  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑   ↑↑↑   ↑↑↑                  ↑↑    ↑↑↑     ↑↑      ↑↑↑    ↑↑       ↑↑↑      ↑↑↑   ↑↑↑      ↑↑↑   ↑↑↑        ↑↑↑
//                    ↑↑↑↑↑↑↑↑↑↑                             ↑↑↑    ↑↑↑    ↑↑↑     ↑↑↑    ↑↑↑↑    ↑↑       ↑↑↑↑↑  ↑↑↑↑     ↑↑↑↑   ↑↑↑    ↑↑↑        ↑↑↑
//                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑                             ↑↑↑↑↑↑       ↑↑↑↑     ↑↑↑↑↑ ↑↑↑    ↑↑       ↑↑↑ ↑↑↑↑↑↑        ↑↑↑↑↑↑      ↑↑↑          ↑↑↑
//                ↑↑↑↑↑  ↑↑↑↑  ↑↑↑↑↑                                                                       ↑↑↑
//              ↑↑↑↑↑    ↑↑↑↑    ↑↑↑↑                                                                      ↑↑↑     Starport: Lending Kernel
//                ↑      ↑↑↑↑     ↑↑↑↑↑
//                       ↑↑↑↑       ↑↑↑↑↑                                                                          Designed with love by Astaria Labs, Inc
//                       ↑↑↑↑         ↑
//                       ↑↑↑↑
//                       ↑↑↑↑
//                       ↑↑↑↑
//                       ↑↑↑↑

pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";

import {StarportLib} from "starport-core/lib/StarportLib.sol";

import "forge-std/console.sol";

contract TestLoanCombinations is StarportTest {
    using {StarportLib.getId} for Starport.Loan;

    function testLoan721for20SimpleInterestDutchFixedRepay() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
        assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

        uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lenderAddress: lender.addr, borrowAmount: 100, terms: terms});

        assertTrue(erc721s[0].balanceOf(borrower.addr) < initial721Balance, "Borrower ERC721 was not sent out");
        assertTrue(erc20s[0].balanceOf(borrower.addr) > initial20Balance, "Borrower did not receive ERC20");

        uint256 loanId = loan.getId();
        assertTrue(SP.open(loanId), "LoanId not in active state after a new loan");
        skip(10 days);

        _repayLoan({borrowerAddress: borrower.addr, amount: 375, loan: loan});
    }

    function testLoan20for20SimpleInterestDutchFixedRepay() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan = _createLoan20Collateral20Debt({
            lenderAddress: lender.addr,
            collateralAmount: 20, // erc20s[1]
            borrowAmount: 100, // erc20s[0]
            terms: terms
        });

        skip(10 days);

        _repayLoan({borrowerAddress: borrower.addr, amount: 375, loan: loan});
    }

    function testLoan20For721SimpleInterestDutchFixedRepay() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan = _createLoan20Collateral721Debt({lenderAddress: lender.addr, terms: terms});
        skip(10 days);

        _repayLoan({borrowerAddress: borrower.addr, amount: 375, loan: loan});
    }

    function testLoanAstariaSettlementRepay() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });
        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lenderAddress: lender.addr, borrowAmount: 100, terms: terms});
        skip(10 days);

        _repayLoan({borrowerAddress: borrower.addr, amount: 375, loan: loan});
    }
}
