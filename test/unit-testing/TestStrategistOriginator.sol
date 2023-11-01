pragma solidity ^0.8.17;

import "starport-test/StarPortTest.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";

contract TestStrategistOriginator is StarPortTest, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;

    event StrategistTransferred(address newStrategist);
    event CounterUpdated(uint256);
    event HashInvalidated(bytes32 hash);

    using {StarPortLib.getId} for LoanManager.Loan;

    uint256 public borrowAmount = 100;

    function setUp() public virtual override {
        super.setUp();
    }

    function testSetStrategist() public {
        vm.expectEmit();
        emit StrategistTransferred(address(this));
        SO.setStrategist(address(this));
    }

    function testEncodeWithAccountCounter() public {
        bytes32 contextHash = keccak256(abi.encodePacked(string("test")));
        bytes32 hash = keccak256(abi.encode(SO.ORIGINATOR_DETAILS_TYPEHASH(), SO.getCounter(), contextHash));

        assert(
            keccak256(SO.encodeWithAccountCounter(contextHash))
                == keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), SO.domainSeparator(), hash))
        );
    }

    function testGetStrategistData() public {
        StrategistOriginator SOO = new StrategistOriginator(LM, strategist.addr, 1e17, address(this));
        (address activeStrategist, uint256 strategistFee) = SOO.getStrategistData();
        assert(activeStrategist == strategist.addr);
        assert(strategistFee == 1e17);
    }

    function testIncrementCounterAsStrategist() public {
        uint256 newCounter = SO.getCounter() + uint256(blockhash(block.number - 1) << 0x80);
        vm.expectEmit();
        emit CounterUpdated(newCounter);
        vm.prank(strategist.addr);
        SO.incrementCounter();
    }

    function testIncrementCounterNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.NotAuthorized.selector));
        vm.prank(address(1));
        SO.incrementCounter();
    }

    function testInvalidDeadline() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(abi.encode(newLoanDetails)))));

        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);

        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);
        skip(200);
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidDeadline.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: abi.encode(newLoanDetails),
                approval: abi.encodePacked(r, s, v)
            })
        );
    }

    function testInvalidCollateral() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        bytes memory encodedLoanDetails = abi.encode(newLoanDetails);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(encodedLoanDetails))));

        loan.collateral[0].identifier = uint256(7);
        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);

        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidCollateral.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: encodedLoanDetails,
                approval: abi.encodePacked(r, s, v)
            })
        );
    }

    function testInvalidDebt() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        bytes memory encodedLoanDetails = abi.encode(newLoanDetails);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(encodedLoanDetails))));

        loan.debt[0].identifier = uint256(7);
        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);

        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidDebt.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: encodedLoanDetails,
                approval: abi.encodePacked(r, s, v)
            })
        );
    }

    function testInvalidDebtAmountRequestingZero() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        bytes memory encodedLoanDetails = abi.encode(newLoanDetails);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(encodedLoanDetails))));

        loan.debt[0].amount = 0;
        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);

        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidDebtAmount.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: encodedLoanDetails,
                approval: abi.encodePacked(r, s, v)
            })
        );
    }

    function testInvalidDebtAmountOfferingZero() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();
        loan.debt[0].amount = 0;

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        bytes memory encodedLoanDetails = abi.encode(newLoanDetails);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(encodedLoanDetails))));

        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);

        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidDebtAmount.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: encodedLoanDetails,
                approval: abi.encodePacked(r, s, v)
            })
        );
    }

    function testInvalidDebtAmountAskingMoreThanOffered() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        bytes memory encodedLoanDetails = abi.encode(newLoanDetails);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(encodedLoanDetails))));

        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);
        loan.debt[0].amount = 2e18;
        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidDebtAmount.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: encodedLoanDetails,
                approval: abi.encodePacked(r, s, v)
            })
        );
    }

    function testInvalidDebtLength() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        bytes memory encodedLoanDetails = abi.encode(newLoanDetails);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(encodedLoanDetails))));

        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);
        SpentItem[] memory newDebt = new SpentItem[](2);
        newDebt[0] = loan.debt[0];
        loan.debt = newDebt;
        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidDebtLength.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: encodedLoanDetails,
                approval: abi.encodePacked(r, s, v)
            })
        );
    }

    function testInvalidSigner() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        bytes memory encodedLoanDetails = abi.encode(newLoanDetails);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(encodedLoanDetails))));

        loan.debt[0].amount = 2e18;

        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);
        SpentItem[] memory newDebt = new SpentItem[](2);
        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidSigner.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: abi.encode(newLoanDetails),
                approval: abi.encodePacked(r, s, v)
            })
        );
    }

    function testInvalidOffer() public {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: LM.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(uint256(1)),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        bytes memory encodedLoanDetails = abi.encode(newLoanDetails);
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(encodedLoanDetails))));

        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);
        SpentItem[] memory newDebt = new SpentItem[](2);
        CaveatEnforcer.CaveatWithApproval memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        LM.setOriginateApproval(address(SO), LoanManager.ApprovalType.LENDER);

        vm.expectEmit();
        emit HashInvalidated(keccak256(encodedLoanDetails));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: encodedLoanDetails,
                approval: abi.encodePacked(r, s, v)
            })
        );
        vm.expectRevert(abi.encodeWithSelector(StrategistOriginator.InvalidOffer.selector));
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: be,
                collateral: loan.collateral,
                debt: loan.debt,
                details: encodedLoanDetails,
                approval: abi.encodePacked(r, s, v)
            })
        );
    }
}
