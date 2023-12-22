// SPDX-License-Identifier: MIT
import "starport-test/StarportTest.sol";
import "starport-test/utils/Bound.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {DeepEq} from "../utils/DeepEq.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {ERC20 as RariERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

contract TestDebt is RariERC20 {
    bool public blocked;

    bool public noReturnData;

    constructor(uint8 decimals) RariERC20("Test20", "TST20", decimals) {
        blocked = false;
        noReturnData = false;
    }

    function blockTransfer(bool blocking) external {
        blocked = blocking;
    }

    function setNoReturnData(bool noReturn) external {
        noReturnData = noReturn;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool ok) {
        if (blocked) {
            return false;
        }

        uint256 allowed = allowance[from][msg.sender];

        if (amount > allowed) {
            revert("NOT_AUTHORIZED");
        }

        super.transferFrom(from, to, amount);

        if (noReturnData) {
            assembly {
                return(0, 0)
            }
        }

        ok = true;
    }

    function increaseAllowance(address spender, uint256 amount) external returns (bool) {
        uint256 current = allowance[msg.sender][spender];
        uint256 remaining = type(uint256).max - current;
        if (amount > remaining) {
            amount = remaining;
        }
        approve(spender, current + amount);
        return true;
    }
}

contract TestFuzzStarport is StarportTest, Bound, DeepEq {
    using FixedPointMathLib for uint256;
    using {StarportLib.getId} for Starport.Loan;

    function setUp() public virtual override {
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

    function boundPricingData(bytes memory boundPricingData) internal view virtual returns (bytes memory pricingData) {
        uint256 min = abi.decode(boundPricingData, (uint256));
        BasePricing.Details memory details = BasePricing.Details({
            rate: _boundMax(min, (uint256(1e16) * 150)),
            carryRate: _boundMax(0, uint256((1e16 * 100))),
            decimals: _boundMax(0, 18)
        });
        pricingData = abi.encode(details);
    }

    function boundStatusData(bytes memory boundStatusData) internal view virtual returns (bytes memory statusData) {
        FixedTermStatus.Details memory boundDetails =
            FixedTermStatus.Details({loanDuration: _boundMax(1 hours, 1095 days)});
        statusData = abi.encode(boundDetails);
    }

    function boundSettlementData(bytes memory boundSettlementData)
        internal
        view
        virtual
        returns (bytes memory settlementData)
    {
        DutchAuctionSettlement.Details memory boundDetails = DutchAuctionSettlement.Details({
            startingPrice: _boundMax(501 ether, 1000 ether),
            endingPrice: _boundMax(1 ether, 500 ether),
            window: _boundMax(1 days, 100 days)
        });
        settlementData = abi.encode(boundDetails);
    }

    function boundFuzzLenderTerms(bytes memory loanBoundsData)
        internal
        view
        virtual
        returns (Starport.Terms memory terms)
    {
        LoanBounds memory loanBounds = abi.decode(loanBoundsData, (LoanBounds));
        terms.status = address(status);
        terms.settlement = address(settlement);
        terms.pricing = address(pricing);
        terms.pricingData = boundPricingData(abi.encode(loanBounds.minPricing));
        terms.statusData = boundStatusData("");
        terms.settlementData = boundSettlementData("");
    }

    struct FuzzLoan {
        bool feesOn;
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

    function boundFuzzLoan(FuzzLoan memory params, bytes memory loanBoundsData)
        internal
        virtual
        returns (Starport.Loan memory loan)
    {
        LoanBounds memory loanBounds = abi.decode(loanBoundsData, (LoanBounds));
        uint256 length = _boundMax(1, 4);
        loan.terms = boundFuzzLenderTerms(loanBoundsData);
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
        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        if (pricingDetails.decimals == 18) {
            debt[0] = SpentItem({
                itemType: ItemType.ERC20,
                identifier: 0,
                amount: _boundMax(params.debtAmount, type(uint128).max),
                token: address(erc20s[1])
            });
        } else {
            TestDebt newDebt = new TestDebt(uint8(pricingDetails.decimals));
            debt[0] = SpentItem({
                itemType: ItemType.ERC20,
                identifier: 0,
                amount: _boundMax(params.debtAmount, type(uint128).max),
                token: address(newDebt)
            });
        }

        loan.debt = debt;
        loan.borrower = borrower.addr;
        loan.custodian = SP.defaultCustodian();
        loan.issuer = lender.addr;
        return loan;
    }

    function willArithmeticOverflow(Starport.Loan memory loan) internal view virtual returns (bool) {
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

    function testFuzzNewOrigination(FuzzLoan memory params) public virtual {
        _generateGoodLoan(params);
    }

    struct LoanBounds {
        uint256 minPricing;
    }

    struct Balances {
        uint256[] collateral;
        uint256[] debt;
        uint256[] borrowerReceivedDebt;
    }

    function fuzzNewLoanOrigination(FuzzLoan memory params, bytes memory loanBoundsData)
        internal
        returns (Starport.Loan memory goodLoan)
    {
        vm.assume(params.collateral.length > 1);
        Starport.Loan memory loan = boundFuzzLoan(params, loanBoundsData);
        vm.assume(!willArithmeticOverflow(loan));

        address feeReceiver = address(20);
        uint256[2][] memory feeRake = new uint256[2][](1);
        feeRake[0][0] = uint256(18);
        feeRake[0][1] = _boundMax(0, 1e17);
        if (params.feesOn) {
            SP.setFeeData(feeReceiver, feeRake);
        }
        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));
        bytes32 borrowerSalt = _boundMinBytes32(0, 0);
        bytes32 lenderSalt = _boundMinBytes32(0, 0);
        address fulfiller;
        if (params.fulfillerType % 2 == 0) {
            fulfiller = loan.borrower;
        } else if (params.fulfillerType % 3 == 0) {
            fulfiller = loan.issuer;
        } else {
            fulfiller = _toAddress(_boundMin(_toUint(params.fulfiller), 100));
        }
        uint256 borrowerDebtBalanceBefore = ERC20(loan.debt[0].token).balanceOf(loan.borrower);

        goodLoan = newLoan(loan, borrowerSalt, lenderSalt, fulfiller);

        if (params.feesOn) {
            assert(
                ERC20(loan.debt[0].token).balanceOf(loan.borrower)
                    == (borrowerDebtBalanceBefore + (loan.debt[0].amount - loan.debt[0].amount.mulWad(feeRake[0][1])))
            );
        } else {
            assert(
                ERC20(loan.debt[0].token).balanceOf(loan.borrower) == (borrowerDebtBalanceBefore + loan.debt[0].amount)
            );
        }
    }

    function boundBadLoan(
        Fuzz.SpentItem[10] memory collateral,
        Fuzz.SpentItem[10] memory debt,
        address[3] memory badAddresses
    ) public virtual returns (Starport.Loan memory loan) {
        uint256 length = _boundMin(0, collateral.length);
        loan.terms = boundFuzzLenderTerms(abi.encode(LoanBounds(0)));
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

    struct FuzzCustodian {
        FuzzLoan origination;
        Fuzz.SpentItem[10] repayCollateral;
        Fuzz.SpentItem[10] repayDebt;
        address[3] badAddresses;
        bool willRepay;
        bool wrongCommand;
    }

    function testFuzzCustodianGeneratePreviewOrder(FuzzCustodian memory params) public {
        Starport.Loan memory goodLoan = _generateGoodLoan(params.origination);

        Custodian.Command memory cmd;

        if (params.willRepay) {
            _skipToRepayment(goodLoan);
            if (!params.wrongCommand) {
                cmd = Custodian.Command(Actions.Repayment, goodLoan, "");
            } else {
                cmd = Custodian.Command(Actions.Settlement, goodLoan, "");
            }
        } else {
            _skipToSettlement(goodLoan);
            if (!params.wrongCommand) {
                cmd = Custodian.Command(Actions.Settlement, goodLoan, "");
            } else {
                cmd = Custodian.Command(Actions.Repayment, goodLoan, "");
            }
        }

        if (params.wrongCommand) {
            vm.expectRevert(Custodian.InvalidAction.selector);
        }
        (SpentItem[] memory pOffer, ReceivedItem[] memory pConsideration) = Custodian(goodLoan.custodian).previewOrder(
            address(consideration), goodLoan.borrower, new SpentItem[](0), new SpentItem[](0), abi.encode(cmd)
        );
        if (params.wrongCommand) {
            vm.expectRevert(Custodian.InvalidAction.selector);
        }
        vm.prank(address(consideration));
        (SpentItem[] memory gOffer, ReceivedItem[] memory gConsideration) = Custodian(goodLoan.custodian).generateOrder(
            goodLoan.borrower, new SpentItem[](0), new SpentItem[](0), abi.encode(cmd)
        );
        if (!params.wrongCommand) {
            _deepEq(pOffer, gOffer);
            _deepEq(pConsideration, gConsideration);
        }
    }

    function testFuzzLoanState(FuzzRepaymentLoan memory params) public {
        Starport.Loan memory badLoan = boundBadLoan(params.repayCollateral, params.repayDebt, params.badAddresses);
        Starport.Loan memory goodLoan = _generateGoodLoan(params.origination);

        badLoan.start = goodLoan.start;
        badLoan.originator = goodLoan.originator;

        assert(goodLoan.originator != address(0));
        assert(SP.open(goodLoan.getId()));
        assert(!SP.closed(goodLoan.getId()));
        assert(SP.closed(badLoan.getId()));
        assert(!SP.open(badLoan.getId()));
    }

    function testFuzzRepaymentFails(FuzzRepaymentLoan memory params) public {
        Starport.Loan memory badLoan = boundBadLoan(params.repayCollateral, params.repayDebt, params.badAddresses);
        Starport.Loan memory goodLoan = _generateGoodLoan(params.origination);

        badLoan.collateral = goodLoan.collateral;
        badLoan.debt = goodLoan.debt;
        badLoan.custodian = goodLoan.custodian;
        skip(1);
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(consideration),
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

        vm.startPrank(badLoan.borrower);
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            TestDebt token = TestDebt(paymentConsideration[i].token);
            token.mint(goodLoan.borrower, paymentConsideration[i].amount);
            token.approve(address(consideration), type(uint256).max);
        }
        if (keccak256(abi.encode(goodLoan)) != keccak256(abi.encode(badLoan))) {
            vm.expectRevert();
        }
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(badLoan.borrower)
        });
        vm.stopPrank();
    }

    function testFuzzRepaymentSuccess(FuzzRepaymentLoan memory params) public {
        Starport.Loan memory goodLoan = _generateGoodLoan(params.origination);
        _skipToRepayment(goodLoan);

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(consideration),
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
            extraData: abi.encode(Custodian.Command(Actions.Repayment, goodLoan, ""))
        });

        vm.startPrank(goodLoan.borrower);
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            TestDebt token = TestDebt(paymentConsideration[i].token);
            token.mint(goodLoan.borrower, paymentConsideration[i].amount);
            token.approve(address(consideration), type(uint256).max);
        }
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
        Starport.Loan memory goodLoan = _generateGoodLoan(params.origination);

        badLoan.collateral = goodLoan.collateral;
        badLoan.debt = goodLoan.debt;
        badLoan.custodian = goodLoan.custodian;

        _skipToSettlement(goodLoan);

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(consideration),
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

        vm.startPrank(badLoan.borrower);
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            TestDebt token = TestDebt(paymentConsideration[i].token);
            token.mint(goodLoan.borrower, paymentConsideration[i].amount);
            token.approve(address(consideration), type(uint256).max);
        }
        if (keccak256(abi.encode(goodLoan)) != keccak256(abi.encode(badLoan))) {
            vm.expectRevert();
        }
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(badLoan.borrower)
        });
        vm.stopPrank();
    }

    function _generateGoodLoan(FuzzLoan memory params) internal virtual returns (Starport.Loan memory) {
        return fuzzNewLoanOrigination(params, abi.encode(LoanBounds(0)));
    }

    function _skipToSettlement(Starport.Loan memory goodLoan) internal virtual {
        FixedTermStatus.Details memory statusDetails = abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details));

        skip(
            _bound(0, abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration, uint256(1000 days))
        );
    }

    function _skipToRepayment(Starport.Loan memory goodLoan) internal virtual {
        skip(_boundMax(1, abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration - 1));
    }

    function testFuzzSettlementSuccess(FuzzSettleLoan memory params) public virtual {
        Starport.Loan memory goodLoan = _generateGoodLoan(params.origination);

        address filler = _toAddress(_boundMin(_toUint(params.origination.fulfiller), 100));
        vm.assume(filler.code.length == 0);
        _skipToSettlement(goodLoan);
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(goodLoan.custodian))
            .previewOrder(
            address(consideration),
            goodLoan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Settlement, goodLoan, ""))
        );
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            erc20s[1].mint(filler, paymentConsideration[i].amount);
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
        for (uint256 i = 0; i < paymentConsideration.length; i++) {
            TestDebt token = TestDebt(paymentConsideration[i].token);
            token.mint(filler, paymentConsideration[i].amount);
            token.approve(address(consideration), type(uint256).max);
        }
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(filler)
        });
        vm.stopPrank();
    }

    function testFuzzRefinance(FuzzRefinanceLoan memory params) public virtual {
        Starport.Loan memory goodLoan = fuzzNewLoanOrigination(params.origination, abi.encode(LoanBounds(1)));

        BasePricing.Details memory oldDetails = abi.decode(goodLoan.terms.pricingData, (BasePricing.Details));

        uint256 newRate = _boundMax(oldDetails.rate - 1, (uint256(1e16) * 1000) / (365 * 1 days));
        BasePricing.Details memory newPricingDetails = BasePricing.Details({
            rate: newRate,
            carryRate: _boundMax(0, uint256((1e16 * 100))),
            decimals: oldDetails.decimals
        });
        Account memory account = makeAndAllocateAccount(params.refiKey);

        address refiFulfiller;
        skip(
            _bound(
                params.skipTime, 1, abi.decode(goodLoan.terms.statusData, (FixedTermStatus.Details)).loanDuration - 1
            )
        );
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
        Starport.Loan memory refiLoan = loanCopy(goodLoan);
        refiLoan.terms.pricingData = abi.encode(newPricingDetails);
        refiLoan.debt = SP.applyRefinanceConsiderationToLoan(considerationPayment, carryPayment);
        LenderEnforcer.Details memory details = LenderEnforcer.Details({loan: refiLoan});
        _issueAndApproveTarget(details.loan.debt, account.addr, address(SP));

        details.loan.issuer = account.addr;
        details.loan.originator = address(0);
        details.loan.start = 0;

        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: details,
            signer: account,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        {
            if (newRate > oldDetails.rate) {
                vm.expectRevert();
            }
            vm.prank(refiFulfiller);
            SP.refinance(
                account.addr,
                refiFulfiller != account.addr ? lenderCaveat : _emptyCaveat(),
                goodLoan2,
                abi.encode(newPricingDetails),
                ""
            );
        }
    }
}
