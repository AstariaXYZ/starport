import "./StarPortTest.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {MockCall} from "starport-test/utils/MockCall.sol";
import "forge-std/Test.sol";

contract TestCustodian is StarPortTest, DeepEq, MockCall {
    using Cast for *;

    LoanManager.Loan public activeLoan;
    LoanManager.Loan public activeLoanWithContractOwner;

    event RepayApproval(address borrower, address repayer, bool approved);

    function setUp() public override {
        super.setUp();

        uint256 borrowAmount = 100;
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        bytes32 conduitKey = bytes32(uint256(uint160(address(this))) << 96);

        address testHelperConduit = conduitController.createConduit(conduitKey, address(this));

        conduitController.updateChannel(testHelperConduit, address(UO), true);
        erc20s[0].approve(address(lenderConduit), 100000);

        selectedCollateral.push(_getERC721Consideration(erc721s[0]));

        debt.push(_getERC20SpentItem(erc20s[0], borrowAmount));

        Originator.Details memory loanDetails = Originator.Details({
            conduit: address(lenderConduit),
            custodian: address(custodian),
            issuer: address(this),
            deadline: block.timestamp + 100,
            offer: Originator.Offer({
                salt: bytes32(0),
                terms: terms,
                collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
                debt: debt
            })
        });

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            Originator(UO),
            selectedCollateral
        );
        Custodian(custodian).mint(loan);

        loan.toStorage(activeLoan);
    }

    function testName() public {
        assertEq(custodian.name(), "Starport Custodian");
    }

    function testSymbol() public {
        assertEq(custodian.symbol(), "SCT");
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

    function testPreviewOrderSettlementInvalidFufiller() public {
        vm.prank(seaportAddr);

        mockHookCall(activeLoan.terms.hook, false);
        mockHandlerCall(activeLoan.terms.handler, new ReceivedItem[](0), address(1));
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidFulfiller.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) =
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
