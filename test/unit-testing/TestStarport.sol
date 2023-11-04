pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {PausableNonReentrant} from "starport-core/lib/PausableNonReentrant.sol";
import {Originator} from "starport-core/originators/Originator.sol";

contract MockOriginator is StrategistOriginator, TokenReceiverInterface {
    constructor(Starport SP_, address strategist_, uint256 fee_)
        StrategistOriginator(SP_, strategist_, fee_, msg.sender)
    {}

    // PUBLIC FUNCTIONS
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        virtual
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC1155BatchReceived.selector;
    }

    function terms(bytes calldata) public view returns (Starport.Terms memory) {
        return Starport.Terms({
            status: address(0),
            settlement: address(0),
            pricing: address(0),
            pricingData: new bytes(0),
            settlementData: new bytes(0),
            statusData: new bytes(0)
        });
    }

    function originate(Request calldata params) external virtual override {
        StrategistOriginator.Details memory details = abi.decode(params.details, (StrategistOriginator.Details));
        _validateOffer(params, details);

        Starport.Loan memory loan = Starport.Loan({
            start: uint256(0), // are set in the loan manager
            originator: address(0), // are set in the loan manager
            custodian: details.custodian,
            issuer: details.issuer,
            borrower: params.borrower,
            collateral: params.collateral,
            debt: params.debt,
            terms: details.offer.terms
        });

        CaveatEnforcer.CaveatWithApproval memory le;
        SP.originate(new AdditionalTransfer[](0), params.borrowerCaveat, le, loan);
    }

    receive() external payable {}
}

contract MockCustodian is Custodian {
    constructor(Starport SP_, ConsiderationInterface seaport) Custodian(SP_, seaport) {}

    function custody(Starport.Loan memory loan) external virtual override onlyStarport returns (bytes4 selector) {}
}

contract TestStarport is StarportTest, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;

    Starport.Loan public activeLoan;

    using {StarportLib.getId} for Starport.Loan;

    uint256 public borrowAmount = 100;
    MockCustodian public mockCustodian;

    event CaveatNonceIncremented(uint256 newNonce);
    event CaveatSaltInvalidated(bytes32 invalidatedSalt);

    event Open(uint256 LoanId, Starport.Loan loan);

    function setUp() public virtual override {
        super.setUp();
        mockCustodian = new MockCustodian(SP, seaport);
        Starport.Loan memory loan = newLoanWithDefaultTerms();
        Custodian(custodian).mint(loan);

        loan.toStorage(activeLoan);
    }

    function testName() public {
        assertEq(SP.name(), "Starport Lending Kernel");
    }

    function testSymbol() public {
        assertEq(SP.symbol(), "SLK");
    }

    function testIncrementCaveatNonce() public {
        vm.roll(5);
        uint256 newNonce = SP.caveatNonces(address(this)) + uint256(blockhash(block.number - 1) << 0x80);
        vm.expectEmit();
        emit CaveatNonceIncremented(newNonce);
        SP.incrementCaveatNonce();
    }

    function testInvalidateCaveatSalt() public {
        bytes32 salt = bytes32(uint256(2));
        vm.expectEmit();
        emit CaveatSaltInvalidated(salt);
        SP.invalidateCaveatSalt(salt);
    }

    function testSupportsInterface() public {
        assertTrue(SP.supportsInterface(bytes4(0x01ffc9a7)));
        assertTrue(SP.supportsInterface(bytes4(0x80ac58cd)));
        assertTrue(SP.supportsInterface(bytes4(0x5b5e139f)));
        assertTrue(SP.supportsInterface(bytes4(0x01ffc9a7)));
    }

    function testCannotSettleUnlessValidCustodian() public {
        vm.expectRevert(abi.encodeWithSelector(Starport.NotLoanCustodian.selector));
        SP.settle(activeLoan);
    }

    function testCannotSettleInvalidLoan() public {
        activeLoan.borrower = address(0);
        vm.prank(activeLoan.custodian);
        vm.expectRevert(abi.encodeWithSelector(Starport.InvalidLoan.selector));
        SP.settle(activeLoan);
    }

    event Paused();
    event Unpaused();

    function testPause() public {
        vm.expectEmit(address(SP));
        emit Paused();
        SP.pause();
    }

    function testUnpause() public {
        SP.pause();
        vm.expectEmit(address(SP));
        emit Unpaused();
        SP.unpause();
    }

    function testApplyRefinanceConsiderationToLoanMalformed() public {
        vm.expectRevert(Starport.MalformedRefinance.selector);
        SP.applyRefinanceConsiderationToLoan(activeLoan, new SpentItem[](0), new SpentItem[](0), "");
    }

    function testInitializedFlagSetProperly() public {
        activeLoan.borrower = address(0);
        assert(SP.inactive(activeLoan.getId()));
    }

    function testActive() public {
        assert(SP.active(activeLoan.getId()));
    }

    function testTokenURI() public {
        assertEq(SP.tokenURI(uint256(keccak256(abi.encode(activeLoan)))), "");
    }

    function testTokenURIInvalidLoan() public {
        vm.expectRevert(abi.encodeWithSelector(Starport.InvalidLoan.selector));
        SP.tokenURI(uint256(0));
    }

    function testTransferFromFail() public {
        vm.expectRevert(abi.encodeWithSelector(Starport.CannotTransferLoans.selector));
        SP.transferFrom(address(this), address(this), uint256(keccak256(abi.encode(activeLoan))));
        vm.expectRevert(abi.encodeWithSelector(Starport.CannotTransferLoans.selector));
        SP.safeTransferFrom(address(this), address(this), uint256(keccak256(abi.encode(activeLoan))));
        vm.expectRevert(abi.encodeWithSelector(Starport.CannotTransferLoans.selector));
        SP.safeTransferFrom(address(this), address(this), uint256(keccak256(abi.encode(activeLoan))), "");
    }

    function testNonDefaultCustodianCustodyCallFails() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.custodian = address(mockCustodian);
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(Starport.InvalidCustodian.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testCannotOriginateWhilePaused() public {
        SP.pause();
        Starport.Loan memory loan = generateDefaultLoanTerms();
        vm.expectRevert(abi.encodeWithSelector(PausableNonReentrant.IsPaused.selector));
        SP.originate(new AdditionalTransfer[](0), _emptyCaveat(), _emptyCaveat(), loan);
    }

    function testNonDefaultCustodianCustodyCallSuccess() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.custodian = address(mockCustodian);
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.mockCall(
            address(mockCustodian),
            abi.encodeWithSelector(Custodian.custody.selector, loan),
            abi.encode(bytes4(Custodian.custody.selector))
        );
        vm.startPrank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidTransferLengthDebt() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        delete loan.debt;
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidTransferLength.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidAmountCollateral() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.collateral[0].amount = 0;
        loan.debt[0].amount = 0;
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemAmount.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidItemType() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].itemType = ItemType.ERC721_WITH_CRITERIA;
        loan.debt[0].token = address(0);
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);

        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemType.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testTokenNoCodeDebt() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.debt[0].token = address(0);
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);

        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemTokenNoCode.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testTokenNoCodeCollateral() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].token = address(0);
        loan.collateral[0].identifier = uint256(2);
        loan.collateral[0].amount = 0;
        loan.debt[0].amount = 0;
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        //        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        //        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemTokenNoCode.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidAmountCollateral721() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.collateral[0].amount = uint256(2);
        loan.debt[0].amount = 0;
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemAmount.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidTransferLengthCollateral() public {
        CaveatEnforcer.CaveatWithApproval memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        delete loan.collateral;
        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidTransferLength.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testDefaultFeeRake() public {
        assertEq(SP.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        SP.setFeeData(feeReceiver, 1e17); //10% fees

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC721SpentItem(erc721s[0], uint256(2)), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        Starport.Loan memory loan =
            newLoan(originationDetails, bytes32(bytes32(msg.sig)), bytes32(bytes32(msg.sig)), lender.addr);
        assertEq(erc20s[0].balanceOf(feeReceiver), loan.debt[0].amount * 1e17 / 1e18, "fee receiver not paid properly");
    }

    function testOverrideFeeRake() public {
        assertEq(SP.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        SP.setFeeData(feeReceiver, 1e17); //10% fees
        SP.setFeeOverride(address(erc20s[0]), 0); //0% fees

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC721SpentItem(erc721s[0], uint256(2)), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        newLoan(originationDetails, bytes32(bytes32(msg.sig)), bytes32(bytes32(msg.sig)), lender.addr);
        assertEq(erc20s[0].balanceOf(feeReceiver), 0, "fee receiver not paid properly");
    }

    // needs modification to work with the new origination flow (unsure if it needs to be elimianted all together)
    function testCaveatEnforcerRevert() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        CaveatEnforcer.CaveatWithApproval memory borrowerEnforcer;
        CaveatEnforcer.CaveatWithApproval memory lenderEnforcer = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        loan.custodian = address(mockCustodian);
        vm.expectRevert();
        SP.originate(new AdditionalTransfer[](0), borrowerEnforcer, lenderEnforcer, loan);
    }

    function testExoticDebtWithNoCaveatsNotAsBorrower() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        SpentItem[] memory exoticDebt = new SpentItem[](2);
        exoticDebt[0] = SpentItem({token: address(erc1155s[1]), amount: 1, identifier: 1, itemType: ItemType.ERC1155});
        exoticDebt[1] = SpentItem({token: address(erc721s[2]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        loan.debt = exoticDebt;
        loan.collateral[0] =
            SpentItem({token: address(erc721s[0]), amount: 1, identifier: 2, itemType: ItemType.ERC721});
        CaveatEnforcer.CaveatWithApproval memory borrowerEnforcer;
        CaveatEnforcer.CaveatWithApproval memory lenderEnforcer = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        Starport.Loan memory loanCopy = abi.decode(abi.encode(loan), (Starport.Loan));
        loanCopy.start = block.timestamp;
        loanCopy.originator = address(loan.borrower);
        vm.expectEmit();
        emit Open(loanCopy.getId(), loanCopy);
        vm.prank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), borrowerEnforcer, lenderEnforcer, loan);
    }

    function testNonPayableFunctions() public {
        vm.expectRevert();
        payable(address(SP)).call{value: 1 ether}(abi.encodeWithSelector(Starport.tokenURI.selector, uint256(0)));
        vm.expectRevert();
        payable(address(SP)).call{value: 1 ether}(abi.encodeWithSelector(ERC721.supportsInterface.selector, bytes4(0)));
        vm.expectRevert();
        payable(address(SP)).call{value: 1 ether}(abi.encodeWithSelector(Starport.name.selector));
        vm.expectRevert();
        payable(address(SP)).call{value: 1 ether}(abi.encodeWithSelector(Starport.symbol.selector));
        CaveatEnforcer.CaveatWithApproval memory be;
        vm.expectRevert();
        payable(address(SP)).call{value: 1 ether}(
            abi.encodeWithSelector(
                Starport.originate.selector, new AdditionalTransfer[](0), be, be, generateDefaultLoanTerms()
            )
        );
        vm.expectRevert();
        payable(address(SP)).call{value: 1 ether}(
            abi.encodeWithSelector(Starport.refinance.selector, address(0), be, generateDefaultLoanTerms(), "")
        );
    }

    //cavets prevent this flow i think, as borrower needs 2 lender caveats to
    function testCannotIssueSameLoanTwice() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc20s[0]), amount: 100, identifier: 0, itemType: ItemType.ERC20});

        loan.debt = exoticDebt;
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc20s[0]), amount: 20, identifier: 0, itemType: ItemType.ERC20});
        loan.collateral = maxSpent;
        CaveatEnforcer.CaveatWithApproval memory be;
        CaveatEnforcer.CaveatWithApproval memory le1 = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        CaveatEnforcer.CaveatWithApproval memory le2 = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(uint256(1)),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        vm.prank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), be, le1, loan);
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.expectRevert(abi.encodeWithSelector(Starport.LoanExists.selector));
        vm.prank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), be, le2, loan);
    }

    function testAdditionalTransfers() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc20s[0]), amount: 100, identifier: 0, itemType: ItemType.ERC20});

        loan.debt = exoticDebt;
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc20s[0]), amount: 20, identifier: 0, itemType: ItemType.ERC20});
        loan.collateral = maxSpent;
        CaveatEnforcer.CaveatWithApproval memory be;
        CaveatEnforcer.CaveatWithApproval memory le1 = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        AdditionalTransfer[] memory additionalTransfers = new AdditionalTransfer[](1);
        additionalTransfers[0] = AdditionalTransfer({
            itemType: ItemType.ERC20,
            token: address(erc20s[0]),
            from: address(loan.borrower),
            to: address(address(20)),
            identifier: 0,
            amount: 20
        });
        vm.prank(loan.borrower);
        ERC20(address(erc20s[0])).approve(address(SP), type(uint256).max);
        vm.prank(loan.borrower);
        SP.originate(additionalTransfers, be, le1, loan);
        assert(erc20s[0].balanceOf(address(20)) == 20);
        assert(erc20s[0].balanceOf(address(loan.custodian)) == 20);
    }
}
