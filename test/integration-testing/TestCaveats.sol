pragma solidity ^0.8.17;

import "starport-test/StarPortTest.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {MockCall} from "starport-test/utils/MockCall.sol";
import "forge-std/Test.sol";
import {StarPortLib, Actions, AdditionalTransfer} from "starport-core/lib/StarPortLib.sol";
import "forge-std/console.sol";

//Informational Finding:
//If you sign a caveat and submit the caveat as the borrower or lender, then it will not be invalidated
//With the current implementations, I think finding a valid refinance may be difficult

contract IntegrationTestCaveats is StarPortTest, DeepEq, MockCall {
    event LogLoan(LoanManager.Loan loan);

    function testOriginateWCaveats() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(loan.borrower);
        LM.originate(new AdditionalTransfer[](0), _emptyCaveat(), lenderCaveat, loan);
    }

    function testOriginateWCaveatsInvalidSalt() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0] = _getERC20SpentItem(erc20s[0], 1000);

        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.startPrank(loan.issuer);
        LM.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);

        vm.expectRevert(StarPortLib.InvalidSalt.selector);
        LM.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateWCaveatsInvalidSaltManual() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(borrower.addr);
        LM.invalidateCaveatSalt(0);

        vm.expectRevert(StarPortLib.InvalidSalt.selector);
        vm.prank(lender.addr);
        LM.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateWCaveatsIncrementedNonce() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(borrower.addr);
        LM.incrementCaveatNonce();

        vm.expectRevert(LoanManager.InvalidCaveatSigner.selector);
        vm.prank(lender.addr);
        LM.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateWBorrowerApproval() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(loan.borrower);
        LM.setOriginateApproval(address(0x5), LoanManager.ApprovalType.BORROWER);
        vm.prank(address(0x5));
        LM.originate(new AdditionalTransfer[](0), _emptyCaveat(), lenderCaveat, loan);
    }

    function testOriginateWLenderApproval() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);
        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(lender.addr);
        LM.setOriginateApproval(address(0x5), LoanManager.ApprovalType.LENDER);
        vm.prank(address(0x5));
        LM.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateUnapprovedFulfiller() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(address(0x5));
        LM.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
    }

    function testRefinanceWCaveatsInvalidSalt() public {
        LoanManager.Loan memory loan = newLoanWithDefaultTerms();

        LenderEnforcer.Details memory details = LenderEnforcer.Details({
            loan: LM.applyRefinanceConsiderationToLoan(loan, loan.debt, new SpentItem[](0), defaultPricingData)
        });

        details.loan.issuer = lender.addr;
        details.loan.originator = address(0);
        details.loan.start = 0;

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: details,
            signer: borrower,
            salt: bytes32(msg.sig),
            enforcer: address(borrowerEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.warp(block.timestamp + 1);
        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));
        vm.expectRevert(StarPortLib.InvalidSalt.selector);
        LM.refinance(lender.addr, lenderCaveat, loan, "");
    }

    function testRefinanceAsLender() public {
        LoanManager.Loan memory loan = newLoanWithDefaultTerms();

        address newLender = address(0x5);
        allocateTokensAndApprovals(newLender, type(uint128).max);
        _setApprovalsForSpentItems(newLender, loan.debt);

        vm.warp(block.timestamp + 1);
        vm.prank(newLender);
        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));
        LM.refinance(newLender, _emptyCaveat(), loan, defaultPricingData);
    }

    function testRefinanceWLenderApproval() public {
        LoanManager.Loan memory loan = newLoanWithDefaultTerms();

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(lender.addr);
        LM.setOriginateApproval(borrower.addr, LoanManager.ApprovalType.LENDER);

        vm.warp(block.timestamp + 1);
        vm.prank(borrower.addr);
        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));
        LM.refinance(lender.addr, _emptyCaveat(), loan, defaultPricingData);
    }

    function testRefinanceUnapprovedFulfiller() public {
        LoanManager.Loan memory loan = newLoanWithDefaultTerms();
        LenderEnforcer.Details memory details = LenderEnforcer.Details({
            loan: LM.applyRefinanceConsiderationToLoan(loan, loan.debt, new SpentItem[](0), defaultPricingData)
        });

        details.loan.issuer = lender.addr;
        details.loan.originator = address(0);
        details.loan.start = 0;

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: details,
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.warp(block.timestamp + 1);

        vm.prank(loan.borrower);

        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));

        LM.refinance(lender.addr, lenderCaveat, loan, defaultPricingData);
    }

    function testRefinanceCaveatFailure() public {
        LoanManager.Loan memory loan = newLoanWithDefaultTerms();

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(loan.borrower);
        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));
        vm.expectRevert(LenderEnforcer.InvalidLoanTerms.selector);
        LM.refinance(lender.addr, lenderCaveat, loan, defaultPricingData);
    }
}
