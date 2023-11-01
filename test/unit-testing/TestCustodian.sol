pragma solidity ^0.8.17;

import "starport-test/StarPortTest.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {MockCall} from "starport-test/utils/MockCall.sol";
import "forge-std/Test.sol";
import {StarPortLib, Actions} from "starport-core/lib/StarPortLib.sol";

contract MockCustodian is Custodian {
    constructor(LoanManager LM_, ConsiderationInterface seaport_) Custodian(LM_, seaport_) {}

    function custody(LoanManager.Loan memory loan)
        external
        virtual
        override
        onlyLoanManager
        returns (bytes4 selector)
    {
        selector = Custodian.custody.selector;
    }
}

contract TestCustodian is StarPortTest, DeepEq, MockCall {
    using Cast for *;

    LoanManager.Loan public activeLoan;

    using {StarPortLib.getId} for LoanManager.Loan;

    event RepayApproval(address borrower, address repayer, bool approved);

    uint256 public borrowAmount = 100;

    function setUp() public virtual override {
        super.setUp();

        erc20s[0].approve(address(lenderConduit), 100000);

        LoanManager.Loan memory loan = newLoanWithDefaultTerms();
        Custodian(custodian).mint(loan);

        loan.toStorage(activeLoan);
    }

    function testPayableFunctions() public {
        vm.deal(seaportAddr, 2 ether);
        vm.prank(seaportAddr);
        payable(address(custodian)).call{value: 1 ether}(abi.encodeWithSignature("helloWorld()"));
        vm.prank(seaportAddr);
        payable(address(custodian)).call{value: 1 ether}("");

        vm.expectRevert(abi.encodeWithSelector(Custodian.NotSeaport.selector));
        payable(address(custodian)).call{value: 1 ether}(abi.encodeWithSignature("helloWorld()"));
        vm.expectRevert(abi.encodeWithSelector(Custodian.NotSeaport.selector));
        payable(address(custodian)).call{value: 1 ether}("");
    }

    function testNonPayableFunctions() public {
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(Custodian.tokenURI.selector, uint256(0))
        );
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(Custodian.getBorrower.selector, uint256(0))
        );
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(Custodian.supportsInterface.selector, bytes4(0))
        );
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(abi.encodeWithSelector(Custodian.name.selector));
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(abi.encodeWithSelector(Custodian.symbol.selector));
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(abi.encodeWithSelector(Custodian.mint.selector, activeLoan));
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(Custodian.setRepayApproval.selector, address(0), false)
        );
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(
                Custodian.ratifyOrder.selector,
                new SpentItem[](0),
                new ReceivedItem[](0),
                new bytes(0),
                new bytes32[](0),
                uint256(0)
            )
        );
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(
                Custodian.generateOrder.selector, address(0), new SpentItem[](0), new SpentItem[](0), new bytes(0)
            )
        );
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(abi.encodeWithSelector(Custodian.custody.selector, activeLoan));
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(abi.encodeWithSelector(Custodian.getSeaportMetadata.selector));
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(
                Custodian.previewOrder.selector,
                address(0),
                address(0),
                new SpentItem[](0),
                new SpentItem[](0),
                new bytes(0)
            )
        );
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(
                Custodian.onERC1155Received.selector, address(0), address(0), uint256(0), uint256(0), new bytes(0)
            )
        );
    }

    function testName() public {
        assertEq(custodian.name(), "Starport Custodian");
    }

    function testSymbol() public {
        assertEq(custodian.symbol(), "SC");
    }

    function testTokenURI() public {
        assertEq(custodian.tokenURI(uint256(keccak256(abi.encode(activeLoan)))), "");
    }

    function testTokenURIInvalidLoan() public {
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        custodian.tokenURI(uint256(0));
    }

    function testSetRepayApproval() public {
        vm.expectEmit(true, false, false, false);
        emit RepayApproval(address(this), borrower.addr, true);
        Custodian(custodian).setRepayApproval(borrower.addr, true);
        assert(Custodian(custodian).repayApproval(address(this), borrower.addr));
    }

    function testCannotMintInvalidLoanValidCustodian() public {
        activeLoan.borrower = address(0);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        Custodian(custodian).mint(activeLoan);
    }

    function testCannotMintInvalidLoanInvalidCustodian() public {
        activeLoan.custodian = address(0);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        Custodian(custodian).mint(activeLoan);
    }

    function testCannotLazyMintTwice() public {
        vm.expectRevert(abi.encodeWithSelector(ERC721.TokenAlreadyExists.selector));
        Custodian(custodian).mint(activeLoan);
    }

    function testSupportsInterface() public {
        assertTrue(custodian.supportsInterface(type(ContractOffererInterface).interfaceId));
        assertTrue(custodian.supportsInterface(type(ERC721).interfaceId));
        assertTrue(custodian.supportsInterface(bytes4(0x5b5e139f)));
        assertTrue(custodian.supportsInterface(bytes4(0x01ffc9a7)));
    }

    function testOnlySeaport() public {
        vm.expectRevert(abi.encodeWithSelector(Custodian.NotSeaport.selector));
        custodian.ratifyOrder(new SpentItem[](0), new ReceivedItem[](0), new bytes(0), new bytes32[](0), uint256(0));

        vm.expectRevert(abi.encodeWithSelector(Custodian.NotSeaport.selector));
        custodian.generateOrder(address(this), new SpentItem[](0), new SpentItem[](0), new bytes(0));
    }

    // no longer applicable since we do not enter through Seaport
    // function testSafeTransfer1155Receive() public {
    //     erc1155s[0].mint(address(this), 1, 2);

    //     vm.expectRevert(abi.encodeWithSelector(Custodian.NotEnteredViaSeaport.selector));
    //     erc1155s[0].safeTransferFrom(address(this), address(custodian), 1, 1, new bytes(0));
    //     vm.store(address(seaport), bytes32(uint256(0)), bytes32(uint256(2)));
    //     erc1155s[0].safeTransferFrom(address(this), address(custodian), 1, 1, new bytes(0));
    // }

    //TODO: make this test meaningful
    function testSeaportMetadata() public view {
        custodian.getSeaportMetadata();
    }

    function testGetBorrower() public {
        assertEq(custodian.getBorrower(activeLoan.toMemory()), activeLoan.borrower);
    }

    function testCustodySelector() public {
        MockCustodian custodianMock = new MockCustodian(LM, seaport);
        vm.prank(address(custodianMock.LM()));
        assert(custodianMock.custody(activeLoan) == Custodian.custody.selector);
    }

    function testDefaultCustodySelectorRevert() public {
        vm.prank(address(custodian.LM()));
        vm.expectRevert(abi.encodeWithSelector(Custodian.ImplementInChild.selector));
        custodian.custody(activeLoan);
    }

    //TODO: add assertions
    function testGenerateOrderRepay() public {
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );
    }
    //TODO: add assertions

    function testGenerateOrderRepayAsRepayApprovedBorrower() public {
        vm.prank(activeLoan.borrower);
        custodian.setRepayApproval(address(this), true);
        vm.prank(seaportAddr);
        custodian.generateOrder(
            address(this), new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );
    }
    //TODO: add assertions

    function testGenerateOrderRepayERC1155WithRevert() public {
        // 1155
        LoanManager.Loan memory originationDetails = _generateOriginationDetails(
            _getERC1155SpentItem(erc1155s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), address(issuer)
        );

        LoanManager.Loan memory loan =
            newLoan(originationDetails, bytes32(uint256(2)), bytes32(uint256(2)), address(issuer));

        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        //function mockCallRevert(address callee, bytes calldata data, bytes calldata revertData) external;
        vm.mockCallRevert(
            address(issuer),
            abi.encodeWithSelector(
                LoanSettledCallback.onLoanSettled.selector, abi.encode(Actions.Repayment, activeLoan)
            ),
            new bytes(0)
        );
        custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );
    }

    function testGenerateOrderRepayERC1155AndERC20AndNativeHandlerAuthorized() public {
        //1155
        LoanManager.Loan memory originationDetails = _generateOriginationDetails(
            _getERC1155SpentItem(erc1155s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), address(issuer)
        );

        LoanManager.Loan memory loan =
            newLoan(originationDetails, bytes32(uint256(3)), bytes32(uint256(3)), address(issuer));

        loan.toStorage(activeLoan);
        mockHookCall(activeLoan.terms.hook, false);

        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(activeLoan.terms.handler));
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        );

        //ERC20
        originationDetails = _generateOriginationDetails(
            _getERC20SpentItem(erc20s[1], borrowAmount + 1), _getERC20SpentItem(erc20s[0], borrowAmount), address(this)
        );

        loan = newLoan(originationDetails, bytes32(uint256(4)), bytes32(uint256(4)), address(this));

        loan.toStorage(activeLoan);

        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        );

        // Native no longer supported unless we add conduti support
        //Native
        // loanDetails = _generateOriginationDetails(
        //     _getNativeConsideration(), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        // );

        // loan = newLoan(
        //     NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
        //     StrategistOriginator(SO),
        //     selectedCollateral
        // );

        // loan.toStorage(activeLoan);

        // vm.prank(seaportAddr);
        // custodian.generateOrder(
        //     activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        // );
    }

    function testGenerateOrderRepayERC1155AndERC20AndNative() public {
        //1155
        LoanManager.Loan memory originationDetails = _generateOriginationDetails(
            _getERC1155SpentItem(erc1155s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), address(issuer)
        );

        LoanManager.Loan memory loan =
            newLoan(originationDetails, bytes32(uint256(5)), bytes32(uint256(5)), address(issuer));

        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );

        //ERC20
        originationDetails = _generateOriginationDetails(
            _getERC20SpentItem(erc20s[1], borrowAmount + 1), _getERC20SpentItem(erc20s[0], borrowAmount), address(this)
        );

        loan = newLoan(originationDetails, bytes32(uint256(6)), bytes32(uint256(6)), address(this));

        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );

        //Native
        // loanDetails = _generateOriginationDetails(
        //     _getNativeConsideration(), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        // );

        // loan = newLoan(
        //     NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
        //     StrategistOriginator(SO),
        //     selectedCollateral
        // );

        // loan.toStorage(activeLoan);

        // vm.prank(seaportAddr);
        // custodian.generateOrder(
        //     activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        // );
    }

    function testGenerateOrderRepayNotBorrower() public {
        vm.prank(seaportAddr);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidRepayer.selector));
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan));
    }

    function testGenerateOrderSettlement() public {
        vm.startPrank(seaportAddr);
        mockHookCall(activeLoan.terms.hook, false);

        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory offer, ReceivedItem[] memory consideration) =
            custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan));

        vm.stopPrank();

        assertEq(consideration.length, 0);
    }

    function testGenerateOrderSettlementHandlerAuthorized() public {
        vm.startPrank(seaportAddr);
        mockHookCall(activeLoan.terms.hook, false);

        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(activeLoan.terms.handler));

        (SpentItem[] memory offer, ReceivedItem[] memory consideration) =
            custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan));

        vm.stopPrank();

        assertEq(consideration.length, 0);
    }

    function testGenerateOrderSettlementUnauthorized() public {
        vm.prank(seaportAddr);
        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), alice);

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidFulfiller.selector));
        custodian.generateOrder(
            borrower.addr, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        );
    }

    function testGenerateOrderSettlementNoActiveLoan() public {
        vm.prank(seaportAddr);
        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), lender.addr);

        activeLoan.borrower = address(bob);
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidLoan.selector));
        custodian.generateOrder(
            borrower.addr, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        );
    }

    //TODO: add assertions
    function testRatifyOrder() public {
        vm.startPrank(seaportAddr);
        bytes memory context = abi.encode(Actions.Repayment, activeLoan);

        (SpentItem[] memory offer, ReceivedItem[] memory consideration) =
            custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), activeDebt, context);

        custodian.ratifyOrder(offer, consideration, context, new bytes32[](0), 0);

        vm.stopPrank();
    }

    function testGenerateOrderInvalidHandlerExecution() public {
        vm.startPrank(seaportAddr);
        bytes memory context = abi.encode(Actions.Settlement, activeLoan);
        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(activeLoan.terms.handler));
        mockHandlerExecuteFail(activeLoan.terms.handler);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidHandlerExecution.selector));
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, context);

        vm.stopPrank();
    }

    function testPreviewOrderRepay() public {
        mockHookCall(activeLoan.terms.hook, true);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            activeLoan.borrower,
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Actions.Repayment, activeLoan)
        );

        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, true);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) = custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );

        _deepEq(receivedOffer, expectedOffer);
        _deepEq(receivedCosideration, expectedConsideration);
    }

    function testGenerateOrderRepayInvalidHookAddress() public {
        vm.prank(seaportAddr);

        destroyAccount(activeLoan.terms.hook, address(0));

        vm.expectRevert();
        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) = custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );
    }

    function testGenerateOrderRepayInvalidHookReturnType() public {
        vm.prank(seaportAddr);

        vm.mockCall(
            activeLoan.terms.hook,
            abi.encodeWithSelector(SettlementHook.isActive.selector),
            abi.encode(string("hello world"))
        );

        vm.expectRevert();
        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) = custodian.generateOrder(
            activeLoan.borrower, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );
    }

    function testPreviewOrderSettlementInvalidFufliller() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(1));
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidFulfiller.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedConsideration) = custodian.previewOrder(
            alice, alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        );
    }

    function testPreviewOrderSettlementInvalidRepayer() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, true);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidRepayer.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            alice, bob, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );
    }

    function testPreviewOrderSettlement() public {
        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            seaportAddr, alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        );

        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));
        vm.prank(seaportAddr);
        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) =
            custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan));

        _deepEq(receivedOffer, expectedOffer);
        _deepEq(receivedCosideration, expectedConsideration);
    }

    function testPreviewOrderNoActiveLoan() public {
        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));
        activeLoan.borrower = address(bob);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            seaportAddr, alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        );
    }

    function testInvalidActionSettleActiveLoan() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, true);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan));

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.previewOrder(
            seaportAddr, alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Settlement, activeLoan)
        );
    }

    function testInvalidActionRepayInActiveLoan() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, false);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan));

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.previewOrder(
            seaportAddr, alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Repayment, activeLoan)
        );
    }

    function testInvalidAction() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, true);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Origination, activeLoan));

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.previewOrder(
            seaportAddr, alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Origination, activeLoan)
        );
    }
}
