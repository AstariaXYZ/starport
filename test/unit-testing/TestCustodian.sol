pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {MockCall} from "starport-test/utils/MockCall.sol";
import "forge-std/Test.sol";
import {StarportLib, Actions} from "starport-core/lib/StarportLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";

contract MockCustodian is Custodian {
    constructor(Starport SP_, address seaport_) Custodian(SP_, seaport_) {}

    function custody(Starport.Loan memory loan) external virtual override onlyStarport returns (bytes4 selector) {
        selector = Custodian.custody.selector;
    }
}

contract TestCustodian is StarportTest, DeepEq, MockCall {
    using Cast for *;

    Starport.Loan public activeLoan;

    using {StarportLib.getId} for Starport.Loan;

    event RepayApproval(address borrower, address repayer, bool approved);

    uint256 public borrowAmount = 100;

    function setUp() public virtual override {
        super.setUp();

        Starport.Loan memory loan = newLoanWithDefaultTerms(false);
        Custodian(custodian).mint(loan);

        loan.toStorage(activeLoan);
        skip(1);
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
        string memory expected = string(
            abi.encodePacked(
                "https://astaria.xyz/metadata/loan/", LibString.toString(uint256(keccak256(abi.encode(activeLoan))))
            )
        );
        assertEq(custodian.tokenURI(uint256(keccak256(abi.encode(activeLoan)))), expected);
    }

    function testTokenURIInvalidLoan() public {
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        custodian.tokenURI(uint256(0));
    }

    event Approval(address owner, address account, uint256 id);

    function testMintWithApprovalSetAsBorrower() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(3);

        newLoan(loan, bytes32(msg.sig), bytes32(msg.sig), borrower.addr);
        loan.start = block.timestamp;
        loan.originator = borrower.addr;
        //        vm.expectEmit();
        //        emit Transfer(address(0), borrower.addr, loan.getId());
        //        vm.expectEmit(address(custodian));
        //        emit Approval(loan.borrower, address(this), loan.getId());
        vm.prank(borrower.addr);
        Custodian(custodian).mintWithApprovalSet(loan, address(this));
        assert(Custodian(custodian).getApproved(loan.getId()) == address(this));
    }

    function testMintWithApprovalSetAsBorrowerInvalidLoan() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(3);
        loan.start = block.timestamp;
        loan.originator = borrower.addr;
        loan.custodian = address(this);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        vm.prank(borrower.addr);
        Custodian(custodian).mintWithApprovalSet(loan, address(this));
    }

    function testMintWithApprovalSetNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(Custodian.NotAuthorized.selector));
        Custodian(custodian).mintWithApprovalSet(activeLoan, address(this));
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

    //TODO: make this test meaningful
    function testSeaportMetadata() public view {
        custodian.getSeaportMetadata();
    }

    function testGetBorrower() public {
        assertEq(custodian.getBorrower(activeLoan.toMemory()), activeLoan.borrower);
    }

    function testCustodySelector() public {
        MockCustodian custodianMock = new MockCustodian(SP, address(seaport));
        vm.prank(address(custodianMock.SP()));
        assert(custodianMock.custody(activeLoan) == Custodian.custody.selector);
    }

    function testDefaultCustodySelectorRevert() public {
        vm.prank(address(custodian.SP()));
        vm.expectRevert(abi.encodeWithSelector(Custodian.ImplementInChild.selector));
        custodian.custody(activeLoan);
    }

    //TODO: add assertions
    function testGenerateOrderRepay() public {
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }
    //TODO: add assertions

    function testGenerateOrderRepayAsRepayApprovedBorrower() public {
        vm.prank(activeLoan.borrower);
        custodian.approve(address(this), activeLoan.getId());
        vm.prank(seaportAddr);
        custodian.generateOrder(
            address(this),
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }

    function testGenerateOrdersWithLoanStartAtBlockTimestampInvalidLoan() public {
        // 1155
        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC1155SpentItem(erc1155s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), address(issuer)
        );

        Starport.Loan memory loan =
            newLoan(originationDetails, bytes32(uint256(2)), bytes32(uint256(2)), address(issuer));
        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }

    function testGenerateOrderRepayERC1155AndERC20HandlerAuthorized() public {
        //1155
        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC1155SpentItem(erc1155s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), address(issuer)
        );

        Starport.Loan memory loan =
            newLoan(originationDetails, bytes32(uint256(3)), bytes32(uint256(3)), address(issuer));
        skip(1);

        loan.toStorage(activeLoan);
        mockStatusCall(activeLoan.terms.status, false);

        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(activeLoan.terms.settlement));
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );

        //ERC20
        originationDetails = _generateOriginationDetails(
            _getERC20SpentItem(erc20s[1], borrowAmount + 1), _getERC20SpentItem(erc20s[0], borrowAmount), address(this)
        );

        loan = newLoan(originationDetails, bytes32(uint256(4)), bytes32(uint256(4)), address(this));

        loan.toStorage(activeLoan);

        skip(1);
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );
    }

    function testGenerateOrderRepayERC1155AndERC20() public {
        //1155
        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC1155SpentItem(erc1155s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), address(issuer)
        );

        Starport.Loan memory loan =
            newLoan(originationDetails, bytes32(uint256(5)), bytes32(uint256(5)), address(issuer));
        skip(1);
        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );

        //ERC20
        originationDetails = _generateOriginationDetails(
            _getERC20SpentItem(erc20s[1], borrowAmount + 1), _getERC20SpentItem(erc20s[0], borrowAmount), address(this)
        );

        loan = newLoan(originationDetails, bytes32(uint256(6)), bytes32(uint256(6)), address(this));
        skip(1);
        loan.toStorage(activeLoan);
        vm.prank(seaportAddr);
        custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }

    function testGenerateOrderRepayNotBorrower() public {
        vm.prank(seaportAddr);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidRepayer.selector));
        custodian.generateOrder(
            alice, new SpentItem[](0), activeDebt, abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }

    function testGenerateOrderSettlement() public {
        vm.startPrank(seaportAddr);
        mockStatusCall(activeLoan.terms.status, false);

        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(0));

        (SpentItem[] memory offer, ReceivedItem[] memory consideration) = custodian.generateOrder(
            alice, new SpentItem[](0), activeDebt, abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );

        vm.stopPrank();

        assertEq(consideration.length, 0);
    }

    function testGenerateOrderSettlementHandlerAuthorized() public {
        vm.startPrank(seaportAddr);
        mockStatusCall(activeLoan.terms.status, false);

        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(activeLoan.terms.settlement));

        (SpentItem[] memory offer, ReceivedItem[] memory consideration) = custodian.generateOrder(
            alice, new SpentItem[](0), activeDebt, abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );

        vm.stopPrank();

        assertEq(consideration.length, 0);
    }

    function testGenerateOrderSettlementUnauthorized() public {
        vm.prank(seaportAddr);
        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), alice);

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidFulfiller.selector));
        custodian.generateOrder(
            borrower.addr,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );
    }

    function testGenerateOrderSettlementNoActiveLoan() public {
        vm.prank(seaportAddr);
        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), lender.addr);

        activeLoan.borrower = address(bob);
        vm.expectRevert(abi.encodeWithSelector(Starport.InvalidLoan.selector));
        custodian.generateOrder(
            borrower.addr,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );
    }

    //TODO: add assertions
    function testRatifyOrder() public {
        vm.startPrank(seaportAddr);
        bytes memory context = abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""));

        (SpentItem[] memory offer, ReceivedItem[] memory consideration) =
            custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), activeDebt, context);

        custodian.ratifyOrder(offer, consideration, context, new bytes32[](0), 0);

        vm.stopPrank();
    }

    function testGenerateOrderInvalidPostSettlement() public {
        vm.startPrank(seaportAddr);
        bytes memory context = abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""));
        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(activeLoan.terms.settlement));
        mockPostSettlementFail(activeLoan.terms.settlement);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidPostSettlement.selector));
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, context);

        vm.stopPrank();
    }

    function testGenerateOrderInvalidPostRepayment() public {
        bytes memory context = abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""));
        mockStatusCall(activeLoan.terms.status, true);
        //        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(activeLoan.terms.settlement));
        mockPostRepaymentFail(activeLoan.terms.settlement);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidPostRepayment.selector));
        vm.prank(seaportAddr);
        custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), activeDebt, context);
    }

    function testPreviewOrderRepay() public {
        mockStatusCall(activeLoan.terms.status, true);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(0));

        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            activeLoan.borrower,
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );

        vm.prank(seaportAddr);

        mockStatusCall(activeLoan.terms.status, true);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(0));

        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) = custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );

        _deepEq(receivedOffer, expectedOffer);
        _deepEq(receivedCosideration, expectedConsideration);
    }

    function testGenerateOrderRepayInvalidHookAddress() public {
        vm.prank(seaportAddr);

        destroyAccount(activeLoan.terms.status, address(0));

        vm.expectRevert();
        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) = custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }

    function testGenerateOrderRepayInvalidHookReturnType() public {
        vm.prank(seaportAddr);

        vm.mockCall(
            activeLoan.terms.status, abi.encodeWithSelector(Status.isActive.selector), abi.encode(string("hello world"))
        );

        vm.expectRevert();
        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) = custodian.generateOrder(
            activeLoan.borrower,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }

    function testPreviewOrderSettlementInvalidFufliller() public {
        vm.prank(seaportAddr);

        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(1));
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidFulfiller.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedConsideration) = custodian.previewOrder(
            alice,
            alice,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );
    }

    function testPreviewOrderSettlementInvalidRepayer() public {
        vm.prank(seaportAddr);

        mockStatusCall(activeLoan.terms.status, true);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(0));
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidRepayer.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            alice, bob, new SpentItem[](0), activeDebt, abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }

    function testPreviewOrderSettlement() public {
        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(0));

        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            seaportAddr,
            alice,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );

        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(0));
        vm.prank(seaportAddr);
        (SpentItem[] memory expectedOffer, ReceivedItem[] memory expectedConsideration) = custodian.generateOrder(
            alice, new SpentItem[](0), activeDebt, abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );

        _deepEq(receivedOffer, expectedOffer);
        _deepEq(receivedCosideration, expectedConsideration);
    }

    function testPreviewOrderNoActiveLoan() public {
        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(0));
        activeLoan.borrower = address(bob);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidLoan.selector));
        (SpentItem[] memory receivedOffer, ReceivedItem[] memory receivedCosideration) = custodian.previewOrder(
            seaportAddr,
            alice,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );
    }

    function testInvalidActionSettleActiveLoan() public {
        vm.prank(seaportAddr);

        mockStatusCall(activeLoan.terms.status, true);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.generateOrder(
            alice, new SpentItem[](0), activeDebt, abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.previewOrder(
            seaportAddr,
            alice,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );
    }

    function testInvalidActionRepayInActiveLoan() public {
        vm.prank(seaportAddr);

        mockStatusCall(activeLoan.terms.status, false);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.generateOrder(
            alice, new SpentItem[](0), activeDebt, abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.previewOrder(
            seaportAddr,
            alice,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Repayment, activeLoan, ""))
        );
    }

    function testInvalidEncodedData() public {
        vm.prank(seaportAddr);

        vm.expectRevert();
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(""));

        vm.expectRevert();
        custodian.previewOrder(seaportAddr, alice, new SpentItem[](0), activeDebt, abi.encode(""));
    }

    function testInvalidAction() public {
        vm.prank(seaportAddr);

        mockStatusCall(activeLoan.terms.status, true);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Nothing, activeLoan));

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.previewOrder(
            seaportAddr, alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Nothing, activeLoan)
        );
        vm.prank(seaportAddr);
        mockStatusCall(activeLoan.terms.status, false);
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.generateOrder(alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Nothing, activeLoan));

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
        custodian.previewOrder(
            seaportAddr, alice, new SpentItem[](0), activeDebt, abi.encode(Actions.Nothing, activeLoan)
        );
    }

    function testCustodianCannotBeAuthorized() public {
        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(custodian));

        vm.expectRevert(abi.encodeWithSelector(Custodian.CustodianCannotBeAuthorized.selector));
        custodian.previewOrder(
            seaportAddr,
            alice,
            new SpentItem[](0),
            activeDebt,
            abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );

        mockStatusCall(activeLoan.terms.status, false);
        mockSettlementCall(activeLoan.terms.settlement, new ReceivedItem[](0), address(custodian));
        vm.prank(seaportAddr);
        vm.expectRevert(abi.encodeWithSelector(Custodian.CustodianCannotBeAuthorized.selector));
        custodian.generateOrder(
            alice, new SpentItem[](0), activeDebt, abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        );
    }
}
