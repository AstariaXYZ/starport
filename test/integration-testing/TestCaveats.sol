pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {MockCall} from "starport-test/utils/MockCall.sol";
import "forge-std/Test.sol";
import {StarportLib, Actions, AdditionalTransfer} from "starport-core/lib/StarportLib.sol";
import "forge-std/console.sol";

//Informational Finding:
//If you sign a caveat and submit the caveat as the borrower or lender, then it will not be invalidated
//With the current implementations, I think finding a valid refinance may be difficult

contract IntegrationTestCaveats is StarportTest, DeepEq, MockCall {
    event LogLoan(Starport.Loan loan);

    using Cast for *;

    Starport.Loan activeLoan;

    function setUp() public override {
        super.setUp();
        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.toStorage(activeLoan);
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
    }

    function testOriginateWCaveatsAsBorrower() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;
        CaveatEnforcer.SignedCaveats memory lenderCaveat;

        borrowerCaveat = _generateSignedCaveatBorrower(activeLoan, borrower, bytes32(0));

        lenderCaveat = _generateSignedCaveatLender(activeLoan, lender, bytes32(0), false);

        newLoan(activeLoan, borrowerCaveat, lenderCaveat, borrower.addr);
    }

    function testOriginateWCaveatsInvalidSalt() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0] = _getERC20SpentItem(erc20s[0], 1000);

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(uint256(1)),
            enforcer: address(borrowerEnforcer),
            singleUse: true
        });

        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.startPrank(loan.issuer);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);

        vm.expectRevert(StarportLib.InvalidSalt.selector);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);

        borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(uint256(1)),
            enforcer: address(borrowerEnforcer),
            singleUse: false
        });

        vm.expectRevert(StarportLib.InvalidSalt.selector);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateWCaveatsExpired() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0] = _getERC20SpentItem(erc20s[0], 1000);

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(uint256(1)),
            enforcer: address(borrowerEnforcer)
        });
        vm.warp(borrowerCaveat.deadline + 1);
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.expectRevert(Starport.CaveatDeadlineExpired.selector);
        vm.startPrank(loan.issuer);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateWCaveatsInvalidSaltManual() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(uint256(1)),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(borrower.addr);
        SP.invalidateCaveatSalt(bytes32(uint256(1)));

        vm.expectRevert(StarportLib.InvalidSalt.selector);
        vm.prank(lender.addr);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateWCaveatsIncrementedNonce() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.roll(5);
        vm.prank(borrower.addr);
        SP.incrementCaveatNonce();

        vm.expectRevert(Starport.InvalidCaveatSigner.selector);
        vm.prank(lender.addr);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testInvalidCaveats() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.roll(5);
        vm.mockCall(
            address(borrowerEnforcer),
            abi.encodeWithSelector(
                CaveatEnforcer.validate.selector, new AdditionalTransfer[](0), loan, borrowerCaveat.caveats[0].data
            ),
            abi.encode(bytes4(0))
        );

        vm.expectRevert(Starport.InvalidCaveat.selector);
        vm.prank(lender.addr);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testInvalidCaveatLength() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.SignedCaveats memory signedCaveats;
        signedCaveats.caveats = new CaveatEnforcer.Caveat[](0);
        signedCaveats.salt = bytes32(0);
        signedCaveats.singleUse = true;
        signedCaveats.deadline = block.timestamp + 1 days;
        bytes32 hash = SP.hashCaveatWithSaltAndNonce(
            borrower.addr, signedCaveats.singleUse, signedCaveats.salt, signedCaveats.deadline, signedCaveats.caveats
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(borrower.key, hash);
        signedCaveats.signature = abi.encodePacked(r, s, v);
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.expectRevert(Starport.InvalidCaveatLength.selector);
        vm.prank(lender.addr);
        SP.originate(new AdditionalTransfer[](0), signedCaveats, _emptyCaveat(), loan);
    }

    function testOriginateWBorrowerApproval() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(loan.borrower);
        SP.setOriginateApproval(address(0x5), Starport.ApprovalType.BORROWER);
        vm.prank(address(0x5));
        SP.originate(new AdditionalTransfer[](0), _emptyCaveat(), lenderCaveat, loan);
    }

    function testOriginateWLenderApproval() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);
        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(lender.addr);
        SP.setOriginateApproval(address(0x5), Starport.ApprovalType.LENDER);
        vm.prank(address(0x5));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, _emptyCaveat(), loan);
    }

    function testOriginateUnapprovedFulfiller() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = getBorrowerSignedCaveat({
            details: BorrowerEnforcer.Details({loan: loan}),
            signer: borrower,
            salt: bytes32(0),
            enforcer: address(borrowerEnforcer)
        });
        _setApprovalsForSpentItems(borrower.addr, loan.collateral);

        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(address(0x5));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
    }

    function testRefinanceWCaveatsInvalidSalt() public {
        Starport.Loan memory loan = newLoanWithDefaultTerms();
        Starport.Loan memory refiLoan = loanCopy(loan);
        refiLoan.debt = SP.applyRefinanceConsiderationToLoan(loan.debt, new SpentItem[](0));
        LenderEnforcer.Details memory details = LenderEnforcer.Details({loan: refiLoan});

        details.loan.issuer = lender.addr;
        details.loan.originator = address(0);
        details.loan.start = 0;

        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: details,
            signer: borrower,
            salt: bytes32(msg.sig),
            enforcer: address(borrowerEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.warp(block.timestamp + 1);
        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));
        vm.expectRevert(StarportLib.InvalidSalt.selector);
        SP.refinance(lender.addr, lenderCaveat, loan, "", "");
    }

    function testRefinanceAsLender() public {
        Starport.Loan memory loan = newLoanWithDefaultTerms();

        address newLender = address(0x5);
        allocateTokensAndApprovals(newLender, type(uint128).max);
        _setApprovalsForSpentItems(newLender, loan.debt);

        vm.warp(block.timestamp + 1);
        vm.prank(newLender);
        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));
        SP.refinance(newLender, _emptyCaveat(), loan, defaultPricingData, "");
    }

    function testRefinanceWLenderApproval() public {
        Starport.Loan memory loan = newLoanWithDefaultTerms();

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(lender.addr);
        SP.setOriginateApproval(borrower.addr, Starport.ApprovalType.LENDER);

        vm.warp(block.timestamp + 1);
        vm.prank(borrower.addr);
        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));
        SP.refinance(lender.addr, _emptyCaveat(), loan, defaultPricingData, "");
    }

    function testRefinanceUnapprovedFulfiller() public {
        Starport.Loan memory loan = newLoanWithDefaultTerms();
        Starport.Loan memory refiLoan = loanCopy(loan);

        refiLoan.debt = SP.applyRefinanceConsiderationToLoan(loan.debt, new SpentItem[](0));
        LenderEnforcer.Details memory details = LenderEnforcer.Details({loan: refiLoan});

        details.loan.issuer = lender.addr;
        details.loan.originator = address(0);
        details.loan.start = 0;

        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: details,
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.warp(block.timestamp + 1);

        vm.prank(loan.borrower);

        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));

        SP.refinance(lender.addr, lenderCaveat, loan, defaultPricingData, "");
    }

    function testRefinanceCaveatFailure() public {
        Starport.Loan memory loan = newLoanWithDefaultTerms();

        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        skip(1);
        vm.prank(loan.borrower);
        mockIsValidRefinanceCall(loan.terms.pricing, loan.debt, new SpentItem[](0), new AdditionalTransfer[](0));
        vm.expectRevert(LenderEnforcer.InvalidLoanTerms.selector);
        SP.refinance(lender.addr, lenderCaveat, loan, defaultPricingData, "");
    }

    function testRefinanceLoanStartAtBlockTimestampInvalidLoan() public {
        Starport.Loan memory loan = newLoanWithDefaultTerms();

        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        _setApprovalsForSpentItems(lender.addr, loan.debt);

        vm.prank(loan.borrower);
        vm.expectRevert(Starport.InvalidLoan.selector);
        SP.refinance(lender.addr, lenderCaveat, loan, defaultPricingData, "");
    }
}
