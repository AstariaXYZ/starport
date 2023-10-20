import "starport-test/StarPortTest.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";

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
        address issuer = address(this);
        if (request.details.length > 0) {
            if (request.debt[0].itemType != ItemType.NATIVE) {
                StrategistOriginator.Details memory details =
                    abi.decode(request.details, (StrategistOriginator.Details));
                issuer = details.issuer == address(0) ? issuer : details.issuer;
                _execute(request, details);
            } else {
                payable(request.receiver).call{value: request.debt[0].amount}("");
            }
        }
        return Response({terms: terms(request.details), issuer: address(this)});
    }

    receive() external payable {}
}

contract MockCustodian is Custodian {
    constructor(LoanManager LM_, ConsiderationInterface seaport) Custodian(LM_, seaport) {}

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
    MockCustodian public mockCustodian;

    function setUp() public virtual override {
        super.setUp();

        erc20s[0].approve(address(lenderConduit), 100000);

        mockCustodian = new MockCustodian(LM, seaport);
        StrategistOriginator.Details memory defaultLoanDetails = _generateOriginationDetails(
            _getERC721Consideration(erc721s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(defaultLoanDetails)),
            StrategistOriginator(SO),
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
            originator: address(SO)
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
            originator: address(SO)
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

    function testInvalidDebtLength() public {
        LoanManager.Obligation memory obligation = LoanManager.Obligation({
            custodian: address(mockCustodian),
            borrower: address(0),
            debt: new SpentItem[](0),
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(SO)
        });
        vm.prank(address(LM.seaport()));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidDebtLength.selector));
        LM.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Origination, obligation)
        );

        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidDebtLength.selector));
        LM.previewOrder(
            address(seaport),
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Origination, obligation)
        );
    }

    function testInvalidDebtType() public {
        MockOriginator MO = new MockOriginator(LM, address(0), 0);
        delete debt;
        debt.push(
            SpentItem({itemType: ItemType.ERC721_WITH_CRITERIA, token: address(erc721s[0]), amount: 100, identifier: 0})
        );
        LoanManager.Obligation memory obligation = LoanManager.Obligation({
            custodian: address(mockCustodian),
            borrower: address(0),
            debt: debt,
            salt: bytes32(0),
            details: "",
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(MO)
        });
        vm.prank(address(LM.seaport()));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidDebtType.selector));
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});
        LM.generateOrder(address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, obligation));

        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidDebtType.selector));
        LM.previewOrder(
            address(seaport), address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, obligation)
        );
    }
    //TODO: make this test meaningful

    function testSeaportMetadata() public view {
        LM.getSeaportMetadata();
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
            originator: address(SO)
        });
        vm.prank(address(LM.seaport()));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidMaximumSpentEmpty.selector));
        LM.generateOrder(
            address(this), new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Origination, obligation)
        );
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidMaximumSpentEmpty.selector));
        LM.previewOrder(
            address(seaport),
            address(this),
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Origination, obligation)
        );
    }

    function testDefaultFeeRake() public {
        assertEq(LM.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        LM.setFeeData(feeReceiver, 1e17); //10% fees

        StrategistOriginator.Details memory defaultLoanDetails = _generateOriginationDetails(
            _getERC721Consideration(erc721s[0], uint256(2)), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(defaultLoanDetails)),
            StrategistOriginator(SO),
            selectedCollateral
        );
        assertEq(erc20s[0].balanceOf(feeReceiver), debt[0].amount * 1e17 / 1e18, "fee receiver not paid properly");
    }

    function testOverrideFeeRake() public {
        assertEq(LM.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        LM.setFeeData(feeReceiver, 1e17); //10% fees
        LM.setFeeOverride(debt[0].token, 0); //0% fees

        StrategistOriginator.Details memory defaultLoanDetails = _generateOriginationDetails(
            _getERC721Consideration(erc721s[0], uint256(2)), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custodian), new LoanManager.Caveat[](0), abi.encode(defaultLoanDetails)),
            StrategistOriginator(SO),
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
        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        SpentItem[] memory expectedOffer = new SpentItem[](2);
        expectedOffer[0] = debt[0];
        expectedOffer[1] =
            SpentItem({itemType: ItemType.ERC721, token: address(LM), identifier: uint256(caveatHash), amount: 1});
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.previewOrder(seaport, address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
        _deepEq(consider, expectedConsider);
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
        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        SpentItem[] memory expectedOffer = new SpentItem[](2);
        expectedOffer[0] = debt[0];
        expectedOffer[0].amount = debt[0].amount - debt[0].amount.mulDiv(1e17, 1e18);
        expectedOffer[1] =
            SpentItem({itemType: ItemType.ERC721, token: address(LM), identifier: uint256(caveatHash), amount: 1});
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.previewOrder(seaport, address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
        _deepEq(consider, expectedConsider);
    }

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

        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        SpentItem[] memory expectedOffer = new SpentItem[](0);
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.previewOrder(seaport, borrower.addr, new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
        _deepEq(consider, expectedConsider);
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
        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        SpentItem[] memory expectedOffer = new SpentItem[](1);
        expectedOffer[0] = debt[0];
        expectedOffer[0].amount = debt[0].amount - debt[0].amount.mulDiv(1e17, 1e18);
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.previewOrder(seaport, borrower.addr, new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
        _deepEq(consider, expectedConsider);
    }

    function testPreviewOrderRefinanceAsRefinancerFeeOn() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        LM.setFeeData(address(20), 1e17); //10% fees

        ReceivedItem[] memory expectedConsideration = new ReceivedItem[](1);
        for (uint256 i; i < debt.length; i++) {
            expectedConsideration[i] = ReceivedItem({
                itemType: debt[i].itemType,
                token: debt[i].token,
                identifier: debt[i].identifier,
                amount: debt[i].amount,
                recipient: payable(activeLoan.issuer)
            });
        }
        (SpentItem[] memory offer, ReceivedItem[] memory originationConsideration) = LM.previewOrder(
            seaport, refinancer.addr, new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Refinance, activeLoan)
        );
        _deepEq(originationConsideration, expectedConsideration);
    }

    function testPreviewOrderRefinanceAsRefinancerFeeOff() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());

        ReceivedItem[] memory expectedConsideration = new ReceivedItem[](1);
        for (uint256 i; i < debt.length; i++) {
            expectedConsideration[i] = ReceivedItem({
                itemType: debt[i].itemType,
                token: debt[i].token,
                identifier: debt[i].identifier,
                amount: debt[i].amount,
                recipient: payable(activeLoan.issuer)
            });
        }
        (SpentItem[] memory offer, ReceivedItem[] memory originationConsideration) = LM.previewOrder(
            seaport, refinancer.addr, new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Refinance, activeLoan)
        );
        _deepEq(originationConsideration, expectedConsideration);
    }

    function testRefinanceNoRefinanceConsideration() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());
        bytes memory newPricingData =
            abi.encode(BasePricing.Details({rate: (uint256(1e16) * 100) / (365 * 1 days), carryRate: 0}));

        vm.mockCall(
            address(activeLoan.terms.pricing),
            abi.encodeWithSelector(Pricing.isValidRefinance.selector, activeLoan, newPricingData, refinancer.addr),
            abi.encode(new ReceivedItem[](0), new ReceivedItem[](0), new ReceivedItem[](0))
        );
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidNoRefinanceConsideration.selector));
        LM.previewOrder(
            seaport,
            refinancer.addr,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Refinance, activeLoan, newPricingData)
        );
        vm.prank(address(LM.seaport()));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidNoRefinanceConsideration.selector));
        LM.generateOrder(
            refinancer.addr,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Refinance, activeLoan, newPricingData)
        );
    }

    function testExoticDebtWithNoCaveatsNotAsBorrower() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());

        SpentItem[] memory exoticDebt = new SpentItem[](2);
        exoticDebt[0] = SpentItem({token: address(erc1155s[1]), amount: 1, identifier: 1, itemType: ItemType.ERC1155});
        exoticDebt[1] = SpentItem({token: address(erc721s[2]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});
        StrategistOriginator.Details memory OD;
        OD.issuer = lender.addr;
        OD.conduit = lenderConduit;
        vm.prank(lender.addr);
        conduitController.updateChannel(lenderConduit, address(originator), true);

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: exoticDebt,
            salt: bytes32(0),
            details: abi.encode(OD),
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        bytes32 caveatHash =
            keccak256(LM.encodeWithSaltAndBorrowerCounter(O.borrower, O.salt, keccak256(abi.encode(O.caveats))));
        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        SpentItem[] memory expectedOffer = new SpentItem[](3);
        expectedOffer[0] = exoticDebt[0];
        expectedOffer[1] = exoticDebt[1];
        expectedOffer[2] =
            SpentItem({itemType: ItemType.ERC721, token: address(LM), identifier: uint256(caveatHash), amount: 1});
        (SpentItem[] memory previewOffer, ReceivedItem[] memory previewConsider) = LM.previewOrder(
            address(LM.seaport()), address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O)
        );
        vm.store(address(seaport), bytes32(uint256(0)), bytes32(uint256(2)));
        vm.prank(address(LM.seaport()));
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.generateOrder(address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
        _deepEq(offer, previewOffer);
        _deepEq(consider, previewConsider);
        _deepEq(consider, expectedConsider);
    }

    function testExoticDebtWithNoCaveatsAsBorrower() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        address seaport = address(LM.seaport());

        SpentItem[] memory exoticDebt = new SpentItem[](2);
        exoticDebt[0] = SpentItem({token: address(erc1155s[1]), amount: 1, identifier: 1, itemType: ItemType.ERC1155});
        exoticDebt[1] = SpentItem({token: address(erc721s[2]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});
        StrategistOriginator.Details memory OD;
        OD.issuer = lender.addr;
        OD.conduit = lenderConduit;
        vm.prank(lender.addr);
        conduitController.updateChannel(lenderConduit, address(originator), true);

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: exoticDebt,
            salt: bytes32(0),
            details: abi.encode(OD),
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        (SpentItem[] memory previewOffer, ReceivedItem[] memory previewConsider) = LM.previewOrder(
            address(LM.seaport()), borrower.addr, new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O)
        );
        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        vm.prank(address(LM.seaport()));
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.generateOrder(borrower.addr, new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, new SpentItem[](0));
        _deepEq(previewOffer, offer);
        _deepEq(consider, previewConsider);
        _deepEq(consider, expectedConsider);
        assert(erc721s[2].ownerOf(1) == borrower.addr);
        assert(erc1155s[1].balanceOf(borrower.addr, 1) == 1);
    }

    function testNativeDebtWithNoCaveatsAsBorrower() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        vm.deal(address(originator), 1 ether);
        address seaport = address(LM.seaport());

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc1155s[1]), amount: 100, identifier: 1, itemType: ItemType.NATIVE});

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});
        StrategistOriginator.Details memory OD;
        OD.issuer = lender.addr;
        OD.conduit = lenderConduit;
        vm.prank(lender.addr);
        conduitController.updateChannel(lenderConduit, address(originator), true);

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: exoticDebt,
            salt: bytes32(0),
            details: abi.encode(OD),
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        ReceivedItem[] memory expectedConsideration = new ReceivedItem[](1);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsideration[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        (SpentItem[] memory previewOffer, ReceivedItem[] memory previewConsider) = LM.previewOrder(
            address(LM.seaport()), borrower.addr, new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O)
        );

        uint256 balanceBefore = borrower.addr.balance;
        vm.prank(address(LM.seaport()));
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.generateOrder(borrower.addr, new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));

        _deepEq(offer, new SpentItem[](0));
        _deepEq(previewOffer, offer);

        _deepEq(consider, previewConsider);
        _deepEq(consider, expectedConsideration);

        assert(borrower.addr.balance == balanceBefore + exoticDebt[0].amount);
    }

    function testNativeDebtWithNoCaveatsNotAsBorrower() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        vm.deal(address(originator), 1 ether);
        address seaport = address(LM.seaport());

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(0), amount: 100, identifier: 1, itemType: ItemType.NATIVE});

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});
        StrategistOriginator.Details memory OD;
        OD.issuer = lender.addr;
        OD.conduit = lenderConduit;
        vm.prank(lender.addr);
        conduitController.updateChannel(lenderConduit, address(originator), true);

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: exoticDebt,
            salt: bytes32(0),
            details: abi.encode(OD),
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        (SpentItem[] memory previewOffer, ReceivedItem[] memory previewConsider) = LM.previewOrder(
            address(LM.seaport()), address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O)
        );

        uint256 balanceOfLM = address(LM).balance;
        //enable re entrancy guard
        vm.store(address(seaport), bytes32(uint256(0)), bytes32(uint256(2)));

        bytes32 caveatHash =
            keccak256(LM.encodeWithSaltAndBorrowerCounter(O.borrower, O.salt, keccak256(abi.encode(O.caveats))));
        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        SpentItem[] memory expectedOffer = new SpentItem[](2);
        expectedOffer[0] = exoticDebt[0];
        expectedOffer[1] =
            SpentItem({itemType: ItemType.ERC721, token: address(LM), identifier: uint256(caveatHash), amount: 1});
        vm.prank(address(LM.seaport()));
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.generateOrder(address(this), new SpentItem[](0), maxSpent, abi.encode(Actions.Origination, O));
        _deepEq(offer, expectedOffer);
        _deepEq(previewOffer, offer);
        _deepEq(consider, previewConsider);
        _deepEq(consider, expectedConsider);
        assert(address(LM).balance == balanceOfLM + exoticDebt[0].amount);
    }

    function testNativeDebtWithNoCaveatsNotAsBorrowerFeesOn() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        vm.deal(address(originator), 1 ether);
        address seaport = address(LM.seaport());

        LM.setFeeData(address(20), 1e17); //10% fees
        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(0), amount: 100, identifier: 1, itemType: ItemType.NATIVE});

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc721s[0]), amount: 1, identifier: 1, itemType: ItemType.ERC721});
        StrategistOriginator.Details memory OD;
        OD.issuer = lender.addr;
        OD.conduit = lenderConduit;
        vm.prank(lender.addr);
        conduitController.updateChannel(lenderConduit, address(originator), true);

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: exoticDebt,
            salt: bytes32(0),
            details: abi.encode(OD),
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        bytes memory encodedObligation = abi.encode(Actions.Origination, O);

        (SpentItem[] memory previewOffer, ReceivedItem[] memory previewConsider) =
            LM.previewOrder(address(LM.seaport()), address(this), new SpentItem[](0), maxSpent, encodedObligation);

        uint256 balanceOfLM = address(LM).balance;
        //enable re entrancy guard
        vm.store(address(seaport), bytes32(uint256(0)), bytes32(uint256(2)));

        bytes32 caveatHash =
            keccak256(LM.encodeWithSaltAndBorrowerCounter(O.borrower, O.salt, keccak256(abi.encode(O.caveats))));

        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }
        SpentItem[] memory expectedOffer = new SpentItem[](2);
        expectedOffer[0] = SpentItemLib.copy(exoticDebt[0]);
        expectedOffer[0].amount = expectedOffer[0].amount - expectedOffer[0].amount.mulDiv(1e17, 1e18);
        expectedOffer[1] =
            SpentItem({itemType: ItemType.ERC721, token: address(LM), identifier: uint256(caveatHash), amount: 1});
        vm.prank(address(LM.seaport()));
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.generateOrder(address(this), new SpentItem[](0), maxSpent, encodedObligation);
        _deepEq(offer, expectedOffer);
        _deepEq(previewOffer, offer);
        _deepEq(consider, expectedConsider);
        _deepEq(consider, previewConsider);

        assert(address(LM).balance == balanceOfLM + expectedOffer[0].amount);
        assert(address(LM.feeTo()).balance == 10);
    }

    function testPayableFunctions() public {
        vm.deal(seaportAddr, 2 ether);
        vm.prank(seaportAddr);
        payable(address(LM)).call{value: 1 ether}(abi.encodeWithSignature("helloWorld()"));
        vm.prank(seaportAddr);
        payable(address(LM)).call{value: 1 ether}("");

        vm.expectRevert(abi.encodeWithSelector(LoanManager.NotSeaport.selector));
        payable(address(LM)).call{value: 1 ether}(abi.encodeWithSignature("helloWorld()"));
        vm.expectRevert(abi.encodeWithSelector(LoanManager.NotSeaport.selector));
        payable(address(LM)).call{value: 1 ether}("");
    }

    function testNonPayableFunctions() public {
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(abi.encodeWithSelector(LoanManager.tokenURI.selector, uint256(0)));
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(
            abi.encodeWithSelector(LoanManager.supportsInterface.selector, bytes4(0))
        );
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(abi.encodeWithSelector(LoanManager.name.selector));
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(abi.encodeWithSelector(LoanManager.symbol.selector));
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(
            abi.encodeWithSelector(
                LoanManager.ratifyOrder.selector,
                new SpentItem[](0),
                new ReceivedItem[](0),
                new bytes(0),
                new bytes32[](0),
                uint256(0)
            )
        );
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(
            abi.encodeWithSelector(
                LoanManager.generateOrder.selector, address(0), new SpentItem[](0), new SpentItem[](0), new bytes(0)
            )
        );
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(abi.encodeWithSelector(LoanManager.getSeaportMetadata.selector));
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(
            abi.encodeWithSelector(
                LoanManager.previewOrder.selector,
                address(0),
                address(0),
                new SpentItem[](0),
                new SpentItem[](0),
                new bytes(0)
            )
        );
        vm.expectRevert();
        payable(address(LM)).call{value: 1 ether}(
            abi.encodeWithSelector(
                LoanManager.onERC1155Received.selector, address(0), address(0), uint256(0), uint256(0), new bytes(0)
            )
        );
    }

    function testSafeTransfer1155Receive() public {
        erc1155s[0].mint(address(this), 1, 1);

        vm.store(address(LM.seaport()), bytes32(uint256(0)), bytes32(uint256(2)));
        erc1155s[0].safeTransferFrom(address(this), address(LM), 1, 1, new bytes(0));
    }

    function testCannotIssueSameLoanTwice() public {
        Originator originator = new MockOriginator(LM, address(0), 0);
        vm.deal(address(originator), 1 ether);
        address seaport = address(LM.seaport());

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(0), amount: 100, identifier: 1, itemType: ItemType.NATIVE});

        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc20s[0]), amount: 20, identifier: 1, itemType: ItemType.ERC20});
        StrategistOriginator.Details memory OD;
        vm.prank(lender.addr);
        conduitController.updateChannel(lenderConduit, address(originator), true);

        LoanManager.Obligation memory O = LoanManager.Obligation({
            custodian: address(custodian),
            borrower: borrower.addr,
            debt: exoticDebt,
            salt: bytes32(0),
            details: abi.encode(OD),
            approval: "",
            caveats: new LoanManager.Caveat[](0),
            originator: address(originator)
        });

        bytes memory encodedObligation = abi.encode(Actions.Origination, O);

        (SpentItem[] memory previewOffer, ReceivedItem[] memory previewConsider) =
            LM.previewOrder(address(LM.seaport()), borrower.addr, new SpentItem[](0), maxSpent, encodedObligation);

        uint256 balanceOfLM = address(LM).balance;
        //enable re entrancy guard
        vm.store(address(seaport), bytes32(uint256(0)), bytes32(uint256(2)));

        ReceivedItem[] memory expectedConsider = new ReceivedItem[](maxSpent.length);
        for (uint256 i; i < maxSpent.length; i++) {
            expectedConsider[i] = ReceivedItem({
                itemType: maxSpent[i].itemType,
                token: maxSpent[i].token,
                identifier: maxSpent[i].identifier,
                amount: maxSpent[i].amount,
                recipient: payable(O.custodian)
            });
        }

        vm.prank(address(LM.seaport()));
        (SpentItem[] memory offer, ReceivedItem[] memory consider) =
            LM.generateOrder(borrower.addr, new SpentItem[](0), maxSpent, encodedObligation);
        _deepEq(offer, new SpentItem[](0));
        _deepEq(previewOffer, offer);
        _deepEq(consider, expectedConsider);
        _deepEq(consider, previewConsider);
        vm.prank(address(LM.seaport()));
        vm.expectRevert(LoanManager.LoanExists.selector);
        LM.generateOrder(borrower.addr, new SpentItem[](0), maxSpent, encodedObligation);
    }
}
