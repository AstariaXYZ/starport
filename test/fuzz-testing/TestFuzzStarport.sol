// SPDX-License-Identifier: MIT
import "starport-test/StarportTest.sol";
import "starport-test/utils/Bound.sol";

contract TestFuzzStarport is StarportTest, Bound {
    function setUp() public override {
        super.setUp();

        vm.warp(100_000);
    }

    function _boundTokenByItemType(ItemType itemType) internal view override returns (address token) {
        if (itemType == ItemType.ERC20) {
            token = address(erc20s[0]);
        } else if (itemType == ItemType.ERC721) {
            token = address(erc721s[0]);
        } else if (itemType == ItemType.ERC1155) {
            token = address(erc1155s[0]);
        } else {
            revert("invalid itemType");
        }
    }

    function _issueAndApproveTarget(SpentItem[] memory what, address who, address target) internal {
        vm.startPrank(who);
        for (uint256 i = 0; i < what.length; i++) {
            if (what[i].itemType == ItemType.ERC20) {
                vm.assume(TestERC20(what[i].token).totalSupply() + what[i].amount < type(uint256).max);
                TestERC20(what[i].token).mint(who, what[i].amount);
                TestERC20(what[i].token).approve(address(target), type(uint256).max);
            } else if (what[i].itemType == ItemType.ERC721) {
                TestERC721(what[i].token).mint(who, what[i].identifier);
                TestERC721(what[i].token).approve(address(target), what[i].identifier);
            } else if (what[i].itemType == ItemType.ERC1155) {
                TestERC1155(what[i].token).mint(who, what[i].identifier, what[i].amount);
                TestERC1155(what[i].token).setApprovalForAll(address(target), true);
            }
        }
        vm.stopPrank();
    }

    function boundPricingData(uint256 min) internal view returns (bytes memory pricingData) {
        BasePricing.Details memory details = BasePricing.Details({
            rate: _boundMax(min, (uint256(1e16) * 150) / (365 * 1 days)),
            carryRate: _boundMax(0, uint256((1e16 * 100)))
        });
        pricingData = abi.encode(details);
    }

    function boundStatusData() internal view returns (bytes memory statusData) {
        FixedTermStatus.Details memory boundDetails =
            FixedTermStatus.Details({loanDuration: _boundMax(1 hours, 1095 days)});
        statusData = abi.encode(boundDetails);
    }

    function boundSettlementData() internal view returns (bytes memory settlementData) {
        DutchAuctionSettlement.Details memory boundDetails = DutchAuctionSettlement.Details({
            startingPrice: _boundMax(501 ether, 1000 ether),
            endingPrice: _boundMax(1 ether, 500 ether),
            window: _boundMax(1 days, 100 days)
        });
        settlementData = abi.encode(boundDetails);
    }

    function boundFuzzLenderTerms() internal view returns (Starport.Terms memory terms) {
        terms.status = address(status);
        terms.settlement = address(settlement);
        terms.pricing = address(pricing);
        terms.pricingData = boundPricingData(0);
        terms.statusData = boundStatusData();
        terms.settlementData = boundSettlementData();
    }

    enum Fulfiller {
        Random,
        Borrower,
        Lender
    }

    struct FuzzLoan {
        address fulfiller;
        Fuzz.SpentItem[] collateral; //array of collateral
        uint8 fulfillerType;
    }

    struct FuzzRefinanceLoan {
        FuzzLoan origination;
        string refiKey;
        uint8 refiFiller;
    }

    struct FuzzRepaymentLoan {
        address fulfiller;
        Fuzz.SpentItem[] collateral;
        Fuzz.SpentItem[10] repayCollateral;
        Fuzz.SpentItem[10] repayDebt;
        address[3] badAddresses;
    }

    function boundFuzzLoan(Fuzz.SpentItem[] memory collateral) internal returns (Starport.Loan memory loan) {
        uint256 length = _boundMin(1, 4);
        loan.terms = boundFuzzLenderTerms();
        uint256 i = 0;
        if (length > collateral.length) {
            length = collateral.length;
        }
        SpentItem[] memory ret = new SpentItem[](length);

        for (; i < length; i++) {
            ret[i] = _boundSpentItem(collateral[i]);
        }
        loan.collateral = ret;
        SpentItem[] memory debt = new SpentItem[](1);
        debt[0] = SpentItem({
            itemType: ItemType.ERC20,
            identifier: 0,
            amount: _boundMin(1, type(uint128).max),
            token: address(erc20s[0])
        });
        loan.debt = debt;
        loan.borrower = borrower.addr;
        loan.custodian = SP.defaultCustodian();
        loan.issuer = lender.addr;
        return loan;
    }

    function willArithmeticOverflow(Starport.Loan memory loan) internal view returns (bool) {
        FixedTermStatus.Details memory statusDetails = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));
        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        try BasePricing(loan.terms.pricing).getPaymentConsideration(loan) returns (
            SpentItem[] memory repayConsideration, SpentItem[] memory carryConsideration
        ) {
            return false;
        } catch {
            return true;
        }
    }

    function testFuzzNewOrigination(FuzzLoan memory params) public returns (Starport.Loan memory) {
        vm.assume(params.collateral.length > 1);
        Starport.Loan memory loan = boundFuzzLoan(params.collateral);
        vm.assume(!willArithmeticOverflow(loan));
        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));

        bytes32 borrowerSalt = _boundMinBytes32(0, type(uint256).max);
        bytes32 lenderSalt = _boundMinBytes32(0, type(uint256).max);
        address fulfiller = _toAddress(_boundMin(_toUint(params.fulfiller), 100));
        return newLoan(loan, borrowerSalt, lenderSalt, fulfiller);
    }

    function boundBadLoan(
        Fuzz.SpentItem[10] memory collateral,
        Fuzz.SpentItem[10] memory debt,
        address[3] memory badAddresses
    ) public returns (Starport.Loan memory loan) {
        uint256 length = _boundMin(0, collateral.length);
        loan.terms = boundFuzzLenderTerms();
        uint256 i = 0;
        SpentItem[] memory ret = new SpentItem[](length);

        for (; i < length; i++) {
            ret[i] = _boundSpentItem(collateral[i], false);
        }
        loan.collateral = ret;
        length = _boundMin(0, debt.length);
        i = 0;

        ret = new SpentItem[](length);
        for (; i < length; i++) {
            ret[i] = _boundSpentItem(debt[i]);
        }
        loan.debt = ret;
        loan.borrower = _toAddress(_boundMin(_toUint(badAddresses[0]), 100));
        loan.custodian = _toAddress(_boundMin(_toUint(badAddresses[1]), 100));
        loan.issuer = _toAddress(_boundMin(_toUint(badAddresses[2]), 100));
        return loan;
    }

    function testFuzzRepaymentFails(FuzzRepaymentLoan memory params) public {
        vm.assume(params.collateral.length > 1);
        Starport.Loan memory badLoan = boundBadLoan(params.repayCollateral, params.repayDebt, params.badAddresses);
        Starport.Loan memory loan = boundFuzzLoan(params.collateral);
        vm.assume(!willArithmeticOverflow(loan));
        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));

        bytes32 borrowerSalt = _boundMinBytes32(0, type(uint256).max);
        bytes32 lenderSalt = _boundMinBytes32(0, type(uint256).max);
        address fulfiller = _toAddress(_boundMin(_toUint(params.fulfiller), 100));
        Starport.Loan memory goodLoan = newLoan(loan, borrowerSalt, lenderSalt, fulfiller);
        badLoan.collateral = loan.collateral;
        badLoan.debt = loan.debt;
        badLoan.custodian = loan.custodian;
        skip(1);
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(SP.seaport()),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Repayment, goodLoan)
        );

        OrderParameters memory op = _buildContractOrder(
            address(goodLoan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Actions.Repayment, badLoan)
        });

        if (keccak256(abi.encode(goodLoan)) != keccak256(abi.encode(badLoan))) {
            vm.expectRevert();
        }
        vm.prank(badLoan.borrower);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(badLoan.borrower)
        });
    }

    function testFuzzRepaymentSuccess(FuzzLoan memory params) public {
        vm.assume(params.collateral.length > 1);
        Starport.Loan memory loan = boundFuzzLoan(params.collateral);
        vm.assume(!willArithmeticOverflow(loan));
        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));

        bytes32 borrowerSalt = _boundMinBytes32(0, type(uint256).max);
        bytes32 lenderSalt = _boundMinBytes32(0, type(uint256).max);
        address fulfiller = _toAddress(_boundMin(_toUint(params.fulfiller), 100));
        Starport.Loan memory goodLoan = newLoan(loan, borrowerSalt, lenderSalt, fulfiller);
        skip(_boundMax(1, abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration - 1));

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(SP.seaport()),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Repayment, goodLoan)
        );
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            erc20s[0].mint(goodLoan.borrower, paymentConsideration[i].amount);
        }

        vm.prank(goodLoan.borrower);
        erc20s[0].approve(address(SP.seaport()), type(uint256).max);

        OrderParameters memory op = _buildContractOrder(
            address(goodLoan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Actions.Repayment, goodLoan)
        });

        vm.prank(goodLoan.borrower);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(goodLoan.borrower)
        });
    }

    function testFuzzSettlementFails(FuzzRepaymentLoan memory params) public {
        vm.assume(params.collateral.length > 1);
        Starport.Loan memory badLoan = boundBadLoan(params.repayCollateral, params.repayDebt, params.badAddresses);
        Starport.Loan memory loan = boundFuzzLoan(params.collateral);
        vm.assume(!willArithmeticOverflow(loan));
        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));

        bytes32 borrowerSalt = _boundMinBytes32(0, type(uint256).max);
        bytes32 lenderSalt = _boundMinBytes32(0, type(uint256).max);
        address fulfiller = _toAddress(_boundMin(_toUint(params.fulfiller), 100));
        Starport.Loan memory goodLoan = newLoan(loan, borrowerSalt, lenderSalt, fulfiller);
        badLoan.collateral = loan.collateral;
        badLoan.debt = loan.debt;
        badLoan.custodian = loan.custodian;
        uint256 skipTime =
            _boundMax(abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration, 1000 days);

        skip(skipTime);
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(SP.seaport()),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Settlement, goodLoan)
        );

        OrderParameters memory op = _buildContractOrder(
            address(goodLoan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Actions.Settlement, badLoan)
        });

        if (keccak256(abi.encode(goodLoan)) != keccak256(abi.encode(badLoan))) {
            vm.expectRevert();
        }
        vm.prank(badLoan.borrower);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(badLoan.borrower)
        });
    }

    function testFuzzSettlementSuccess(FuzzLoan memory params) public {
        vm.assume(params.collateral.length > 1);
        Starport.Loan memory loan = boundFuzzLoan(params.collateral);
        vm.assume(!willArithmeticOverflow(loan));
        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));

        bytes32 borrowerSalt = _boundMinBytes32(0, type(uint256).max);
        bytes32 lenderSalt = _boundMinBytes32(0, type(uint256).max);
        address fulfiller = _toAddress(_boundMin(_toUint(params.fulfiller), 100));
        Starport.Loan memory goodLoan = newLoan(loan, borrowerSalt, lenderSalt, fulfiller);
        FixedTermStatus.Details memory statusDetails = abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details));

        skip(_boundMax(abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration, 1000 days));

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(SP.seaport()),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Settlement, goodLoan)
        );
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            erc20s[0].mint(goodLoan.borrower, paymentConsideration[i].amount);
        }

        vm.prank(goodLoan.borrower);
        erc20s[0].approve(address(SP.seaport()), type(uint256).max);

        OrderParameters memory op = _buildContractOrder(
            address(goodLoan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Actions.Settlement, goodLoan)
        });

        vm.prank(goodLoan.borrower);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(goodLoan.borrower)
        });
    }

    function testFuzzRefinance(FuzzRefinanceLoan memory params) public {
        vm.assume(params.origination.collateral.length > 1);
        Starport.Loan memory loan = boundFuzzLoan(params.origination.collateral);
        loan.terms.pricingData = boundPricingData(1);
        vm.assume(!willArithmeticOverflow(loan));
        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));

        bytes32 borrowerSalt = _boundMinBytes32(0, type(uint256).max);
        bytes32 lenderSalt = _boundMinBytes32(0, type(uint256).max);

        address fulfiller;
        if (params.origination.fulfillerType % 2 == 0) {
            fulfiller = loan.borrower;
        } else if (params.origination.fulfillerType % 3 == 0) {
            fulfiller = loan.issuer;
        } else {
            fulfiller = _toAddress(_boundMin(_toUint(params.origination.fulfiller), 100));
        }
        Starport.Loan memory goodLoan = newLoan(loan, borrowerSalt, lenderSalt, fulfiller);

        uint256 oldRate = abi.decode(goodLoan.terms.pricingData, (BasePricing.Details)).rate;

        uint256 newRate = _boundMax(oldRate - 1, (uint256(1e16) * 1000) / (365 * 1 days));
        BasePricing.Details memory newPricingDetails = BasePricing.Details({rate: newRate, carryRate: 0});
        Account memory account = makeAndAllocateAccount(params.refiKey);

        address refiFulfiller;
        skip(_boundMax(1, abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration));
        (
            SpentItem[] memory considerationPayment,
            SpentItem[] memory carryPayment,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(goodLoan.terms.pricing).getRefinanceConsideration(
            goodLoan, abi.encode(newPricingDetails), refiFulfiller
        );
        if (params.origination.fulfillerType % 2 == 0) {
            refiFulfiller = loan.borrower;
        } else if (params.origination.fulfillerType % 3 == 0) {
            refiFulfiller = account.addr;
        } else {
            refiFulfiller = _toAddress(_boundMin(0, 100));
        }
        LenderEnforcer.Details memory details = LenderEnforcer.Details({
            loan: SP.applyRefinanceConsiderationToLoan(
                goodLoan, considerationPayment, carryPayment, abi.encode(newPricingDetails)
                )
        });
        _issueAndApproveTarget(details.loan.debt, account.addr, address(SP));

        details.loan.issuer = account.addr;
        details.loan.originator = address(0);
        details.loan.start = 0;

        CaveatEnforcer.CaveatWithApproval memory lenderCaveat = getLenderSignedCaveat({
            details: details,
            signer: account,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        if (newRate > oldRate) {
            vm.expectRevert();
        }
        vm.prank(refiFulfiller);
        SP.refinance(
            account.addr,
            refiFulfiller != account.addr ? lenderCaveat : _emptyCaveat(),
            goodLoan,
            abi.encode(newPricingDetails)
        );
    }
}
