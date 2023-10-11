import "./StarPortTest.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {MockCall} from "starport-test/utils/MockCall.sol";
import "forge-std/Test.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {LoanSettledCallback} from "starport-core/Custodian.sol";

contract MockIssuer is LoanSettledCallback, TokenReceiverInterface {
    function onLoanSettled(LoanManager.Loan memory loan) external {}

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

contract TestCustodian is StarPortTest, DeepEq, MockCall {
    using Cast for *;

    LoanManager.Loan public activeLoan;

    using {StarPortLib.getId} for LoanManager.Loan;

    event RepayApproval(address borrower, address repayer, bool approved);

    uint256 public borrowAmount = 100;
    MockIssuer public issuer;

    function setUp() public override {
        super.setUp();

        erc20s[0].approve(address(lenderConduit), 100000);
        issuer = new MockIssuer();
        vm.label(address(issuer), "MockIssuer");
        conduitKey = bytes32(uint256(uint160(address(issuer))) << 96);

        erc20s[0].mint(address(issuer), 100000);
        vm.prank(address(issuer));
        erc20s[0].approve(address(lenderConduit), 100000);
        Originator.Details memory loanDetails = _generateOriginationDetails(
            _getERC721Consideration(erc721s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            Originator(UO),
            selectedCollateral
        );
        Custodian(custodian).mint(loan);

        loan.toStorage(activeLoan);
    }

    function _generateOriginationDetails(
        ConsiderationItem memory collateral,
        SpentItem memory debtRequested,
        address incomingIssuer
    ) internal returns (Originator.Details memory details) {
        delete selectedCollateral;
        delete debt;
        selectedCollateral.push(collateral);
        debt.push(debtRequested);
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        details = Originator.Details({
            conduit: address(lenderConduit),
            custodian: address(custodian),
            issuer: incomingIssuer,
            deadline: block.timestamp + 100,
            offer: Originator.Offer({
                salt: bytes32(0),
                terms: terms,
                collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
                debt: debt
            })
        });
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
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(
                Custodian.custody.selector, new ReceivedItem[](0), new bytes32[](0), uint256(0), new bytes(0)
            )
        );
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
                Custodian.onERC721Received.selector, address(0), address(0), uint256(0), new bytes(0)
            )
        );
        vm.expectRevert();
        payable(address(custodian)).call{value: 1 ether}(
            abi.encodeWithSelector(
                Custodian.onERC1155BatchReceived.selector,
                address(0),
                address(0),
                new uint256[](0),
                new uint256[](0),
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

    function testSafeTransferReceive() public {
        erc721s[0].mint(address(this), 0x1a4);
        erc721s[0].safeTransferFrom(address(this), address(custodian), 0x1a4);

        erc1155s[0].mint(address(this), 1, 2);
        erc1155s[0].mint(address(this), 2, 2);

        erc1155s[0].safeTransferFrom(address(this), address(custodian), 1, 1, new bytes(0));

        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        erc1155s[0].safeBatchTransferFrom(address(this), address(custodian), ids, amounts, new bytes(0));
    }

    //TODO: make this test meaningful
    function testSeaportMetadata() public view {
        custodian.getSeaportMetadata();
    }

    function testGetBorrower() public {
        assertEq(custodian.getBorrower(activeLoan.toMemory()), activeLoan.borrower);
    }

    function testCustodySelector() public {
        assert(
            custodian.custody(new ReceivedItem[](0), new bytes32[](0), uint256(0), new bytes(0))
                == Custodian.custody.selector
        );
    }

    //TODO: add assertions
    function testGenerateOrderRepay() public {
        vm.prank(seaportAddr);
        custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));
    }
    //TODO: add assertions

    function testGenerateOrderRepayAsRepayApprovedBorrower() public {
        vm.prank(activeLoan.borrower);
        custodian.setRepayApproval(address(this), true);
        vm.prank(seaportAddr);
        custodian.generateOrder(address(this), new SpentItem[](0), debt, abi.encode(activeLoan));
    }
    //TODO: add assertions

    function testGenerateOrderRepayERC1155WithRevert() public {
        //1155
        Originator.Details memory loanDetails = _generateOriginationDetails(
            _getERC1155Consideration(erc1155s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), address(issuer)
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            Originator(UO),
            selectedCollateral
        );

        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        //function mockCallRevert(address callee, bytes calldata data, bytes calldata revertData) external;
        vm.mockCallRevert(
            address(issuer),
            abi.encodeWithSelector(LoanSettledCallback.onLoanSettled.selector, abi.encode(activeLoan)),
            new bytes(0)
        );
        custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testGenerateOrderRepayERC1155AndERC20AndNative() public {
        //1155
        Originator.Details memory loanDetails = _generateOriginationDetails(
            _getERC1155Consideration(erc1155s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), address(issuer)
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            Originator(UO),
            selectedCollateral
        );

        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));

        //ERC20
        loanDetails = _generateOriginationDetails(
            _getERC20Consideration(erc20s[1]), _getERC20SpentItem(erc20s[0], borrowAmount), address(this)
        );

        loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            Originator(UO),
            selectedCollateral
        );

        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));

        //Native
        loanDetails = _generateOriginationDetails(
            _getNativeConsideration(), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            Originator(UO),
            selectedCollateral
        );

        loan.toStorage(activeLoan);

        vm.prank(seaportAddr);
        custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testGenerateOrderRepayNotBorrower() public {
        vm.prank(seaportAddr);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidRepayer.selector));
        custodian.generateOrder(alice, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testGenerateOrderSettlement() public {
        vm.startPrank(seaportAddr);
        mockHookCall(activeLoan.terms.hook, false);

        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory offer, ReceivedItem[] memory consideration) =
            custodian.generateOrder(alice, new SpentItem[](0), debt, abi.encode(activeLoan));

        vm.stopPrank();

        assertEq(consideration.length, 0);
    }

    function testGenerateOrderSettlementUnauthorized() public {
        vm.prank(seaportAddr);
        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), lender.addr);

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidFulfiller.selector));
        custodian.generateOrder(borrower.addr, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testGenerateOrderSettlementNoActiveLoan() public {
        vm.prank(seaportAddr);
        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), lender.addr);

        activeLoan.borrower = address(bob);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        custodian.generateOrder(borrower.addr, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    //TODO: add assertions
    function testRatifyOrder() public {
        vm.startPrank(seaportAddr);
        bytes memory context = abi.encode(activeLoan);

        (SpentItem[] memory offer, ReceivedItem[] memory consideration) =
            custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, context);

        custodian.ratifyOrder(offer, consideration, context, new bytes32[](0), 0);

        vm.stopPrank();
    }

    function testRatifyOrderInvalidHandlerExecution() public {
        vm.startPrank(seaportAddr);
        bytes memory context = abi.encode(activeLoan);

        mockHandlerExecuteFail(activeLoan.terms.handler);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidHandlerExecution.selector));
        custodian.ratifyOrder(new SpentItem[](0), new ReceivedItem[](0), context, new bytes32[](0), 0);

        vm.stopPrank();
    }

    function testPreviewOrderRepay() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, true);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) =
            custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));

        mockHookCall(activeLoan.terms.hook, true);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            activeLoan.borrower, activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan)
        );

        _deepEq(receivedOffer, expectedOffer);
        _deepEq(receivedCosideration, expectedConsideration);
    }

    function testGenerateOrderRepayInvalidHookAddress() public {
        vm.prank(seaportAddr);

        destroyAccount(activeLoan.terms.hook, address(0));

        vm.expectRevert();
        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) =
            custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testGenerateOrderRepayInvalidHookReturnType() public {
        vm.prank(seaportAddr);

        vm.mockCall(
            activeLoan.terms.hook,
            abi.encodeWithSelector(SettlementHook.isActive.selector),
            abi.encode(string("hello world"))
        );

        vm.expectRevert();
        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) =
            custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testPreviewOrderSettlementInvalidFufliller() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(1));
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidFulfiller.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedConsideration) =
            custodian.previewOrder(alice, alice, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testPreviewOrderSettlementInvalidRepayer() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, true);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidRepayer.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) =
            custodian.previewOrder(alice, bob, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testPreviewOrderSettlement() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) =
            custodian.generateOrder(alice, new SpentItem[](0), debt, abi.encode(activeLoan));

        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));

        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) =
            custodian.previewOrder(seaportAddr, alice, new SpentItem[](0), debt, abi.encode(activeLoan));

        _deepEq(receivedOffer, expectedOffer);
        _deepEq(receivedCosideration, expectedConsideration);
    }

    function testPreviewOrderNoActiveLoan() public {
        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(0));
        activeLoan.borrower = address(bob);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) =
            custodian.previewOrder(seaportAddr, alice, new SpentItem[](0), debt, abi.encode(activeLoan));
    }
}
