import "./StarPortTest.sol";

contract TestCustodian is StarPortTest {
    using Cast for *;

    LoanManager.Loan public activeLoan;

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

        selectedCollateral.push(_getERC721Consideration(erc721s[0]));

        debt.push(_getERC20SpentItem(erc20s[0], borrowAmount));

        Originator.Details memory loanDetails = Originator.Details({
            conduit: address(lenderConduit),
            custodian: address(custodian),
            issuer: lender.addr,
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

        loan.toStorage(activeLoan);
    }

    function testSupportsInterface() public {
        assertTrue(custodian.supportsInterface(type(ContractOffererInterface).interfaceId));
    }

    function testOnlySeaport() public {
        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidSender.selector));
        custodian.ratifyOrder(new SpentItem[](0), new ReceivedItem[](0), new bytes(0), new bytes32[](0), uint256(0));

        vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidSender.selector));
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

    function testGetBorrower() public view {
        custodian.getBorrower(activeLoan.toMemory());
    }

    function testCustodySelector() public {
        assert(
            custodian.custody(new ReceivedItem[](0), new bytes32[](0), uint256(0), new bytes(0))
                == Custodian.custody.selector
        );
    }

    function testGenerateOrder() public {
        vm.prank(seaportAddr);
        custodian.generateOrder(activeLoan.borrower, new SpentItem[](0), debt, abi.encode(activeLoan));
    }

    function testRatifyOrder() public {}

    function testPreviewOrder() public {}
}
