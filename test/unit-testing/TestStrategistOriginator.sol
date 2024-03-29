pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";

contract TestStrategistOriginator is StarportTest, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;

    event StrategistTransferred(address newStrategist);
    event CounterUpdated(uint256);
    event HashInvalidated(bytes32 hash);

    using {StarportLib.getId} for Starport.Loan;

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

    function testIncrementCounterAsStrategist() public {
        uint256 newCounter = SO.getCounter() + 1 + uint256(blockhash(block.timestamp - 1) >> 0x80);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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

        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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

        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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

        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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

        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.debt[0].amount = 0;

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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

        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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
        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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
        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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
        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
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
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.timestamp + 8,
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
        CaveatEnforcer.SignedCaveats memory be = _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5)));
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);

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

    function testWithdraw() public {
        vm.startPrank(borrower.addr);
        erc721s[0].transferFrom(borrower.addr, address(SO), 1);
        erc20s[1].transfer(address(SO), 10_000);
        erc1155s[0].safeTransferFrom(borrower.addr, address(SO), 1, 1, "");
        vm.stopPrank();

        SpentItem[] memory spentItems = new SpentItem[](3);

        spentItems[0] = SpentItem({itemType: ItemType.ERC721, token: address(erc721s[0]), identifier: 1, amount: 1});
        spentItems[1] = SpentItem({itemType: ItemType.ERC20, token: address(erc20s[1]), identifier: 0, amount: 10_000});
        spentItems[2] = SpentItem({itemType: ItemType.ERC1155, token: address(erc1155s[0]), identifier: 1, amount: 1});

        uint256 balanceBefore = erc20s[1].balanceOf(strategist.addr);
        address owner = SO.owner();
        vm.startPrank(owner);
        SO.withdraw(spentItems, strategist.addr);
        vm.stopPrank();

        assertEq(
            erc721s[0].ownerOf(1), strategist.addr, "erc721s not transferred properly on StrategistOriginator withdraw"
        );
        assertEq(
            erc20s[1].balanceOf(strategist.addr) - balanceBefore,
            10_000,
            "erc20s not transferred properly on StrategistOriginator withdraw"
        );
        assertEq(
            erc1155s[0].balanceOf(strategist.addr, 1),
            1,
            "erc1155s not transferred properly on StrategistOriginator withdraw"
        );
    }
}
