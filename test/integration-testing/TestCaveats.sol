pragma solidity ^0.8.17;

import "starport-test/StarPortTest.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {MockCall} from "starport-test/utils/MockCall.sol";
import "forge-std/Test.sol";
import {StarPortLib, Actions} from "starport-core/lib/StarPortLib.sol";
import "forge-std/console.sol";

//Informational Finding:
//If you sign a caveat and submit the caveat as the borrower or lender, then it will not be invalidated
//Can the borrower refinance there own loan in this setup?

contract IntegrationTestCaveats is StarPortTest, DeepEq, MockCall {
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
        LM.originate(new ConduitTransfer[](0), _emptyCaveat(), lenderCaveat, loan);
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
        LM.originate(new ConduitTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);

        vm.expectRevert(StarPortLib.InvalidSalt.selector);
        LM.originate(new ConduitTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateWCaveatsInvalidSaltManual() public {
        vm.prank(lender.addr);
        LM.invalidateCaveatSalt(msg.sig);
        vm.expectRevert(StarPortLib.InvalidSalt.selector);
        newLoanWithDefaultTerms();
    }

    function testOriginateWCaveatsIncrementedNonce() public {
        vm.prank(lender.addr);
        LM.incrementCaveatNonce();
        vm.expectRevert(LoanManager.InvalidCaveatSigner.selector);
        newLoanWithDefaultTerms();
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
        LM.originate(new ConduitTransfer[](0), _emptyCaveat(), lenderCaveat, loan);
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
        LM.originate(new ConduitTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
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
        LM.originate(new ConduitTransfer[](0), borrowerCaveat, lenderCaveat, loan);
    }

    //Test Refinance with caveats
    function testRefinanceWCaveats() public {
        LoanManager.Loan memory loan = newLoanWithDefaultTerms();

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(loan.borrower);
        mockIsValidRefinanceCall(loan.terms.pricing, new SpentItem[](0), new SpentItem[](0), new ConduitTransfer[](0));
        LM.refinance(lender.addr, lenderCaveat, loan, "");
    }

    function testRefinanceWCaveatsInvalidSalt() public {
        LoanManager.Loan memory loan = newLoanWithDefaultTerms();
        loan.collateral[0] = _getERC20SpentItem(erc20s[0], 1000);

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(msg.sig),
            enforcer: address(borrowerEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.expectRevert(StarPortLib.InvalidSalt.selector);
        LM.refinance(lender.addr, lenderCaveat, loan, "");
    }

    function testRefinanceWLenderApproval() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(lender.addr);
        LM.setOriginateApproval(borrower.addr, LoanManager.ApprovalType.LENDER);

        vm.prank(borrower.addr);
        mockIsValidRefinanceCall(loan.terms.pricing, new SpentItem[](0), new SpentItem[](0), new ConduitTransfer[](0));
        LM.refinance(lender.addr, _emptyCaveat(), loan, "");
    }

    function testRefinanceUnapprovedFulfiller() public {
        LoanManager.Loan memory loan = newLoanWithDefaultTerms();

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(loan.borrower);
        mockIsValidRefinanceCall(loan.terms.pricing, new SpentItem[](0), new SpentItem[](0), new ConduitTransfer[](0));
        LM.refinance(lender.addr, lenderCaveat, loan, "");
    }

    //Test caveat enforcement revert

    //Test multiple caveats
}
