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
                unchecked {
                    uint256 newSupply = TestERC20(what[i].token).totalSupply() + (what[i].amount * 2);
                    if (newSupply < TestERC20(what[i].token).totalSupply() || newSupply < what[i].amount) {
                        vm.assume(false);
                    }
                }
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
            carryRate: _boundMax(min, uint256((1e16 * 100)))
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

    function boundFuzzLenderTerms(LoanBounds memory loanBounds) internal view returns (Starport.Terms memory terms) {
        terms.status = address(status);
        terms.settlement = address(settlement);
        terms.pricing = address(pricing);
        terms.pricingData = boundPricingData(loanBounds.minPricing);
        terms.statusData = boundStatusData();
        terms.settlementData = boundSettlementData();
    }

    struct FuzzLoan {
        address fulfiller;
        uint256 debtAmount;
        uint256 rate;
        uint256 carryRate;
        uint256 collateralLength;
        Fuzz.SpentItem[] collateral; //array of collateral
        uint8 fulfillerType;
    }

    struct FuzzRefinanceLoan {
        FuzzLoan origination;
        string refiKey;
        uint8 refiFiller;
        uint256 newRate;
        uint256 newCarryRate;
        uint256 skipTime;
    }

    struct FuzzSettleLoan {
        FuzzLoan origination;
        uint256 skipTime;
    }

    struct FuzzRepaymentLoan {
        FuzzLoan origination;
        Fuzz.SpentItem[10] repayCollateral;
        Fuzz.SpentItem[10] repayDebt;
        address[3] badAddresses;
        uint256 skipTime;
    }

    function boundFuzzLoan(FuzzLoan memory params, LoanBounds memory loanBounds)
        internal
        returns (Starport.Loan memory loan)
    {
        uint256 length = _boundMax(1, 4);
        loan.terms = boundFuzzLenderTerms(loanBounds);
        uint256 i = 0;
        if (length > params.collateral.length) {
            length = params.collateral.length;
        }
        SpentItem[] memory ret = new SpentItem[](length);

        for (; i < length; i++) {
            ret[i] = _boundSpentItem(params.collateral[i]);
        }
        loan.collateral = ret;
        SpentItem[] memory debt = new SpentItem[](1);
        debt[0] = SpentItem({
            itemType: ItemType.ERC20,
            identifier: 0,
            amount: _boundMin(params.debtAmount, type(uint128).max),
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
            unchecked {
                uint256 newSupply = erc20s[0].totalSupply() + repayConsideration[0].amount;
                if (newSupply < erc20s[0].totalSupply() || newSupply < repayConsideration[0].amount) {
                    return true;
                }
            }
            return false;
        } catch {
            return true;
        }
    }

    function testFuzzNewOrigination(FuzzLoan memory params) public {
        fuzzNewLoanOrigination(params, LoanBounds(0));
    }

    struct LoanBounds {
        uint256 minPricing;
    }

    function fuzzNewLoanOrigination(FuzzLoan memory params, LoanBounds memory loanBounds)
        internal
        returns (Starport.Loan memory)
    {
        vm.assume(params.collateral.length > 1);
        Starport.Loan memory loan = boundFuzzLoan(params, loanBounds);
        vm.assume(!willArithmeticOverflow(loan));

        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));
        bytes32 borrowerSalt = _boundMinBytes32(0, type(uint256).max);
        bytes32 lenderSalt = _boundMinBytes32(0, type(uint256).max);
        address fulfiller;
        if (params.fulfillerType % 2 == 0) {
            fulfiller = loan.borrower;
        } else if (params.fulfillerType % 3 == 0) {
            fulfiller = loan.issuer;
        } else {
            fulfiller = _toAddress(_boundMin(_toUint(params.fulfiller), 100));
        }
        return newLoan(loan, borrowerSalt, lenderSalt, fulfiller);
    }

    function boundBadLoan(
        Fuzz.SpentItem[10] memory collateral,
        Fuzz.SpentItem[10] memory debt,
        address[3] memory badAddresses
    ) public returns (Starport.Loan memory loan) {
        uint256 length = _boundMin(0, collateral.length);
        loan.terms = boundFuzzLenderTerms(LoanBounds(0));
        uint256 i = 0;
        SpentItem[] memory ret = new SpentItem[](length);

        for (; i < length; i++) {
            ret[i] = _boundSpentItem(collateral[i]);
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
        Starport.Loan memory badLoan = boundBadLoan(params.repayCollateral, params.repayDebt, params.badAddresses);
        Starport.Loan memory goodLoan = fuzzNewLoanOrigination(params.origination, LoanBounds(0));

        badLoan.collateral = goodLoan.collateral;
        badLoan.debt = goodLoan.debt;
        badLoan.custodian = goodLoan.custodian;
        skip(1);
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(SP.seaport()),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Repayment, goodLoan, ""))
        );

        OrderParameters memory op = _buildContractOrder(
            address(goodLoan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Custodian.Command(Actions.Repayment, badLoan, ""))
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

    function testFuzzRepaymentSuccess(FuzzRepaymentLoan memory params) public {
        Starport.Loan memory goodLoan = fuzzNewLoanOrigination(params.origination, LoanBounds(0));
        skip(_boundMax(1, abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration - 1));

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(SP.seaport()),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Repayment, goodLoan, ""))
        );
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            erc20s[0].mint(goodLoan.borrower, paymentConsideration[i].amount);
        }

        OrderParameters memory op = _buildContractOrder(
            address(goodLoan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Custodian.Command(Actions.Repayment, goodLoan, ""))
        });

        vm.startPrank(goodLoan.borrower);
        erc20s[0].approve(address(SP.seaport()), type(uint256).max);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(goodLoan.borrower)
        });
        vm.stopPrank();
    }

    function testFuzzSettlementFails(FuzzRepaymentLoan memory params) public {
        Starport.Loan memory badLoan = boundBadLoan(params.repayCollateral, params.repayDebt, params.badAddresses);
        Starport.Loan memory goodLoan = fuzzNewLoanOrigination(params.origination, LoanBounds(0));

        badLoan.collateral = goodLoan.collateral;
        badLoan.debt = goodLoan.debt;
        badLoan.custodian = goodLoan.custodian;

        skip(
            _bound(
                params.skipTime,
                abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration,
                1000 days
            )
        );

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(SP.seaport()),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Settlement, goodLoan, ""))
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

    function testFuzzSettlementSuccess(FuzzSettleLoan memory params) public {
        Starport.Loan memory goodLoan = fuzzNewLoanOrigination(params.origination, LoanBounds(0));

        address filler = _toAddress(_boundMin(_toUint(params.origination.fulfiller), 100));
        FixedTermStatus.Details memory statusDetails = abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details));

        skip(
            _bound(
                params.skipTime,
                abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration,
                uint256(1000 days)
            )
        );
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(SP.seaport()),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Settlement, goodLoan, ""))
        );
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            erc20s[0].mint(filler, paymentConsideration[i].amount);
        }

        OrderParameters memory op = _buildContractOrder(
            address(goodLoan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Custodian.Command(Actions.Settlement, goodLoan, ""))
        });

        vm.startPrank(filler);
        erc20s[0].approve(address(SP.seaport()), type(uint256).max);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(filler)
        });
        vm.stopPrank();
    }

    function testFuzzRefinance(FuzzRefinanceLoan memory params) public {
        Starport.Loan memory goodLoan = fuzzNewLoanOrigination(params.origination, LoanBounds(1));

        uint256 oldRate = abi.decode(goodLoan.terms.pricingData, (BasePricing.Details)).rate;

        uint256 newRate = _boundMax(oldRate - 1, (uint256(1e16) * 1000) / (365 * 1 days));
        BasePricing.Details memory newPricingDetails =
            BasePricing.Details({rate: newRate, carryRate: _boundMax(0, uint256((1e16 * 100)))});
        Account memory account = makeAndAllocateAccount(params.refiKey);

        address refiFulfiller;
        skip(1);
        skip(_boundMax(params.skipTime, abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration));
        (
            SpentItem[] memory considerationPayment,
            SpentItem[] memory carryPayment,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(goodLoan.terms.pricing).getRefinanceConsideration(
            goodLoan, abi.encode(newPricingDetails), refiFulfiller
        );
        if (params.origination.fulfillerType % 2 == 0) {
            refiFulfiller = goodLoan.borrower;
        } else if (params.origination.fulfillerType % 3 == 0) {
            refiFulfiller = account.addr;
        } else {
            refiFulfiller = _toAddress(_boundMin(params.skipTime, 100));
        }
        Starport.Loan memory goodLoan2 = goodLoan;
        LenderEnforcer.Details memory details = LenderEnforcer.Details({
            loan: SP.applyRefinanceConsiderationToLoan(
                goodLoan2, considerationPayment, carryPayment, abi.encode(newPricingDetails)
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
        {
            if (newRate > oldRate) {
                vm.expectRevert();
            }
            vm.prank(refiFulfiller);
            SP.refinance(
                account.addr,
                refiFulfiller != account.addr ? lenderCaveat : _emptyCaveat(),
                goodLoan2,
                abi.encode(newPricingDetails)
            );
        }
    }
}
