import "starport-test/StarPortTest.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract MockOriginator is StrategistOriginator, TokenReceiverInterface {
    constructor(LoanManager LM_, address strategist_, uint256 fee_)
        StrategistOriginator(LM_, strategist_, fee_, msg.sender)
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

    function terms(bytes calldata) public view returns (LoanManager.Terms memory) {
        return LoanManager.Terms({
            hook: address(0),
            handler: address(0),
            pricing: address(0),
            pricingData: new bytes(0),
            handlerData: new bytes(0),
            hookData: new bytes(0)
        });
    }

    function execute(Request calldata request) external override returns (Response memory response) {
        return Response({terms: terms(request.details), issuer: address(this)});
    }
}

contract MockCustodian is Custodian {
    constructor(LoanManager LM_, address seaport) Custodian(LM_, seaport) {}

    function custody(
        ReceivedItem[] calldata consideration,
        bytes32[] calldata orderHashes,
        uint256 contractNonce,
        bytes calldata context
    ) external virtual override onlyLoanManager returns (bytes4 selector) {}
}

contract TestLoanManager is StarPortTest, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;

    LoanManager.Loan public activeLoan;

    using {StarPortLib.getId} for LoanManager.Loan;

    uint256 public borrowAmount = 100;
    MockCustodian mockCustodian = new MockCustodian(LM, address(seaport));

    function setUp() public virtual override {
        super.setUp();

        erc20s[0].approve(address(lenderConduit), 100000);

        mockCustodian = new MockCustodian(LM, address(seaport));
        Originator.Details memory defaultLoanDetails = _generateOriginationDetails(
            _getERC721Consideration(erc721s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(defaultLoanDetails)),
            Originator(UO),
            selectedCollateral
        );
        Custodian(custodian).mint(loan);

        loan.toStorage(activeLoan);
    }

    function testName() public {
        assertEq(LM.name(), "Starport Loan Manager");
    }

    function testSymbol() public {
        assertEq(LM.symbol(), "SLM");
    }

    function testSupportsInterface() public {
        assertTrue(LM.supportsInterface(type(ContractOffererInterface).interfaceId));
        assertTrue(LM.supportsInterface(type(ERC721).interfaceId));
        assertTrue(LM.supportsInterface(bytes4(0x5b5e139f)));
        assertTrue(LM.supportsInterface(bytes4(0x01ffc9a7)));
    }

    function testGenerateOrderNotSeaport() public {
        vm.expectRevert(abi.encodeWithSelector(LoanManager.NotSeaport.selector));
        LM.generateOrder(address(this), new SpentItem[](0), new SpentItem[](0), new bytes(0));
    }

    function testGenerateOrder() public {
        StrategistOriginator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        //
        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        //        OrderParameters memory op = _buildContractOrder(address(LM), new OfferItem[](0), selectedCollateral);
        vm.startPrank(seaport);
        (SpentItem[] memory offer, ReceivedItem[] memory consideration) =
            LM.generateOrder(address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        //TODO:: validate return data matches request
        //        assertEq(keccak256(abi.encode(consideration)), keccak256(abi.encode(maxSpent)));
    }

    function testCannotSettleUnlessValidCustodian() public {
        vm.expectRevert(abi.encodeWithSelector(LoanManager.NotLoanCustodian.selector));
        LM.settle(activeLoan);
    }

    function testCannotSettleInvalidLoan() public {
        activeLoan.borrower = address(0);
        vm.prank(activeLoan.custodian);
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidLoan.selector));
        LM.settle(activeLoan);
    }

    function testIssued() public {
        assert(LM.issued(activeLoan.getId()));
    }

    function testInitializedFlagSetProperly() public {
        activeLoan.borrower = address(0);
        assert(LM.initialized(activeLoan.getId()));
    }

    function testTokenURI() public {
        assertEq(LM.tokenURI(uint256(keccak256(abi.encode(activeLoan)))), "");
    }

    function testTokenURIInvalidLoan() public {
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidLoan.selector));
        LM.tokenURI(uint256(0));
    }

    function testTransferFromFailFromSeaport() public {
        vm.startPrank(address(LM.seaport()));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.CannotTransferLoans.selector));
        LM.transferFrom(address(this), address(this), uint256(keccak256(abi.encode(activeLoan))));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.CannotTransferLoans.selector));
        LM.safeTransferFrom(address(this), address(this), uint256(keccak256(abi.encode(activeLoan))));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.CannotTransferLoans.selector));
        LM.safeTransferFrom(address(this), address(this), uint256(keccak256(abi.encode(activeLoan))), "");
        vm.stopPrank();
    }

    function testNonDefaultCustodianCustodyCallFails() public {
        LoanManager.Obligation memory obligation = LoanManager.Obligation({
            custodian: address(mockCustodian),
            borrower: address(0),
            debt: new SpentItem[](0),
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(UO)
        });
        vm.prank(address(LM.seaport()));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidCustodian.selector));
        LM.ratifyOrder(
            new SpentItem[](0),
            new ReceivedItem[](0),
            abi.encode(Actions.Origination, obligation),
            new bytes32[](0),
            uint256(0)
        );
    }

    function testNonDefaultCustodianCustodyCallSuccess() public {
        LoanManager.Obligation memory obligation = LoanManager.Obligation({
            custodian: address(mockCustodian),
            borrower: address(0),
            debt: new SpentItem[](0),
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(UO)
        });

        vm.mockCall(
            address(mockCustodian),
            abi.encodeWithSelector(
                Custodian.custody.selector,
                new ReceivedItem[](0),
                new bytes32[](0),
                uint256(0),
                abi.encode(Actions.Origination, obligation)
            ),
            abi.encode(bytes4(Custodian.custody.selector))
        );
        vm.prank(address(LM.seaport()));
        LM.ratifyOrder(
            new SpentItem[](0),
            new ReceivedItem[](0),
            abi.encode(Actions.Origination, obligation),
            new bytes32[](0),
            uint256(0)
        );
    }

    function testInvalidDebt() public {
        LoanManager.Obligation memory obligation = LoanManager.Obligation({
            custodian: address(mockCustodian),
            borrower: address(0),
            debt: new SpentItem[](0),
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(UO)
        });
        vm.prank(address(LM.seaport()));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidDebt.selector));
        LM.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Origination, obligation)
        );
    }

    function testInvalidMaximumSpentEmpty() public {
        LoanManager.Obligation memory obligation = LoanManager.Obligation({
            custodian: address(mockCustodian),
            borrower: address(0),
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(UO)
        });
        vm.prank(address(LM.seaport()));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidMaximumSpentEmpty.selector));
        LM.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Origination, obligation)
        );
    }

    function testDefaultFeeRake() public {
        assertEq(LM.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        LM.setFeeData(feeReceiver, 1e17); //10% fees

        Originator.Details memory defaultLoanDetails = _generateOriginationDetails(
            _getERC721Consideration(erc721s[0], uint256(2)), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(defaultLoanDetails)),
            Originator(UO),
            selectedCollateral
        );
        assertEq(erc20s[0].balanceOf(feeReceiver), debt[0].amount * 1e17 / 1e18, "fee receiver not paid properly");
    }

    function testOverrideFeeRake() public {
        assertEq(LM.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        LM.setFeeData(feeReceiver, 1e17); //10% fees
        LM.setFeeOverride(debt[0].token, 0); //0% fees

        Originator.Details memory defaultLoanDetails = _generateOriginationDetails(
            _getERC721Consideration(erc721s[0], uint256(2)), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(defaultLoanDetails)),
            Originator(UO),
            selectedCollateral
        );
        assertEq(erc20s[0].balanceOf(feeReceiver), 0, "fee receiver not paid properly");
    }

    function testCaveatEnforcerInvalidOrigination() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        TermEnforcer TE = new TermEnforcer();

        LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
        caveats[0] = LoanManager.Caveat({enforcer: address(TE), terms: ""});
        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: caveats,
            originator: address(originator)
        });

        LoanManager.Loan memory mockLoan = LoanManager.Loan({
            start: block.timestamp,
            borrower: O.borrower,
            collateral: maxSpent,
            issuer: O.originator,
            custodian: O.custodian,
            debt: debt,
            originator: O.originator,
            terms: LoanManager.Terms({
                hook: address(0),
                hookData: new bytes(0),
                pricing: address(0),
                pricingData: new bytes(0),
                handler: address(0),
                handlerData: new bytes(0)
            })
        });
        vm.mockCall(
            address(TE),
            abi.encodeWithSelector(TermEnforcer.enforceCaveat.selector, bytes(""), mockLoan),
            abi.encode(false)
        );
        vm.startPrank(seaport);
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidOrigination.selector));
        LM.generateOrder(address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
    }

    function testGenerateOrderInvalidAction() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        //
        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        vm.startPrank(seaport);
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidAction.selector));
        LM.generateOrder(address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Repayment, O));
    }

    function testPreviewOrderInvalidAction() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        vm.startPrank(seaport);
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidAction.selector));
        LM.previewOrder(seaport, address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Repayment, O));
    }

    function testPreviewOrderOriginationWithNoCaveatsSetNotBorrowerNoFee() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        delete debt;
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        bytes32 caveatHash =
            keccak256(LM.encodeWithSaltAndBorrowerCounter(O.borrower, O.salt, keccak256(abi.encode(O.caveats))));

        SpentItem[] memory expectedOffer = new SpentItem[](2);
        expectedOffer[0] = debt[0];
        expectedOffer[1] =
            SpentItem({itemType: ItemType.ERC721, token: address(LM), identifier: uint256(caveatHash), amount: 1});
        (SpentItem[] memory offer, ReceivedItem[] memory originationConsideration) =
            LM.previewOrder(seaport, address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
    }

    function testPreviewOrderOriginationWithNoCaveatsSetNotBorrowerFeeOn() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        LM.setFeeData(address(20), 1e17); //10% fees
        delete debt;
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        bytes32 caveatHash =
            keccak256(LM.encodeWithSaltAndBorrowerCounter(O.borrower, O.salt, keccak256(abi.encode(O.caveats))));

        SpentItem[] memory expectedOffer = new SpentItem[](2);
        expectedOffer[0] = debt[0];
        expectedOffer[0].amount = debt[0].amount - debt[0].amount.mulWad(1e17);
        expectedOffer[1] =
            SpentItem({itemType: ItemType.ERC721, token: address(LM), identifier: uint256(caveatHash), amount: 1});
        (SpentItem[] memory offer, ReceivedItem[] memory originationConsideration) =
            LM.previewOrder(seaport, address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
    }

    event log_spentItem(SpentItem[] spentItem);

    function testPreviewOrderOriginationWithNoCaveatsSetAsBorrowerNoFee() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        console.log(LM.feeTo());
        delete debt;
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        SpentItem[] memory expectedOffer = new SpentItem[](0);
        (SpentItem[] memory offer, ReceivedItem[] memory originationConsideration) =
            LM.previewOrder(seaport, borrower.addr, new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
    }

    function testPreviewOrderOriginationWithNoCaveatsSetAsBorrowerFeeOn() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        LM.setFeeData(address(20), 1e17); //10% fees
        delete debt;
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        SpentItem[] memory expectedOffer = new SpentItem[](1);
        expectedOffer[0] = debt[0];
        expectedOffer[0].amount = debt[0].amount - debt[0].amount.mulWad(1e17);
        (SpentItem[] memory offer, ReceivedItem[] memory originationConsideration) =
            LM.previewOrder(seaport, borrower.addr, new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
    }
}
