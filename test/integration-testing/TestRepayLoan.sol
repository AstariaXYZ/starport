pragma solidity ^0.8.17;

import "starport-test/StarPortTest.sol";
import {SimpleInterestPricing} from "starport-core/pricing/SimpleInterestPricing.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";

contract TestRepayLoan is StarPortTest {
    function testRepayLoan() public {
        uint256 borrowAmount = 1e18;
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        uint256 borrowerBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBefore = erc20s[0].balanceOf(lender.addr);

        vm.startPrank(borrower.addr);
        skip(10 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest =
            SimpleInterestPricing(loan.terms.pricing).calculateInterest(10 days, loan.debt[0].amount, details.rate);
        erc20s[0].approve(address(LM.seaport()), borrowAmount + interest);
        vm.stopPrank();

        _executeRepayLoan(loan);

        uint256 borrowerAfter = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderAfter = erc20s[0].balanceOf(lender.addr);

        assertEq(
            borrowerBefore - loan.debt[0].amount + interest,
            borrowerAfter,
            "borrower: Borrower repayment was not correct"
        );
        assertEq(
            lenderBefore + loan.debt[0].amount + interest, lenderAfter, "lender: Borrower repayment was not correct"
        );
    }
}
