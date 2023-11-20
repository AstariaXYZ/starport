pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {PausableNonReentrant} from "starport-core/lib/PausableNonReentrant.sol";
import {Originator} from "starport-core/originators/Originator.sol";

import {Validation} from "starport-core/lib/Validation.sol";

contract MockFixedTermDutchAuctionSettlement is DutchAuctionSettlement {
    using {StarportLib.getId} for Starport.Loan;
    using FixedPointMathLib for uint256;

    address public debtToken;

    constructor(Starport SP_, address debtToken_) DutchAuctionSettlement(SP_) {
        debtToken = debtToken_;
    }

    // @inheritdoc DutchAuctionSettlement
    function getAuctionStart(Starport.Loan calldata loan) public view virtual override returns (uint256) {
        FixedTermStatus.Details memory details = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));
        return loan.start + details.loanDuration;
    }

    function getSettlementConsideration(Starport.Loan calldata loan)
        public
        view
        virtual
        override
        returns (ReceivedItem[] memory consideration, address authorized)
    {
        Details memory details = abi.decode(loan.terms.settlementData, (Details));

        uint256 start = getAuctionStart(loan);

        // DutchAuction has failed, allow lender to redeem
        if (start + details.window < block.timestamp) {
            return (new ReceivedItem[](0), loan.issuer);
        }

        uint256 settlementPrice = _locateCurrentAmount({
            startAmount: details.startingPrice,
            endAmount: details.endingPrice,
            startTime: start,
            endTime: start + details.window,
            roundUp: true
        });

        consideration = new ReceivedItem[](1);

        consideration[0] = ReceivedItem({
            itemType: ItemType.ERC20,
            identifier: 0,
            amount: settlementPrice,
            token: debtToken,
            recipient: payable(loan.issuer)
        });
    }
}

contract MockExoticPricing is Pricing {
    error NoRefinance();

    using FixedPointMathLib for uint256;
    using {StarportLib.getId} for Starport.Loan;

    struct Details {
        uint256 rate;
        uint256 carryRate;
        uint256 decimals;
        address token;
        uint256 debtAmount;
    }

    constructor(Starport SP_) Pricing(SP_) {}

    function getPaymentConsideration(Starport.Loan calldata loan)
        public
        view
        virtual
        override
        returns (SpentItem[] memory repayConsideration, SpentItem[] memory carryConsideration)
    {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));
        if (details.carryRate > 0 && loan.issuer != loan.originator) {
            carryConsideration = new SpentItem[](loan.debt.length + 1);
        } else {
            carryConsideration = new SpentItem[](0);
        }
        repayConsideration = new SpentItem[](loan.debt.length + 1);

        repayConsideration[0] = loan.debt[0];

        if (carryConsideration.length > 1) {
            SpentItem memory empty;
            carryConsideration[0] = empty;
        }
        uint256 i = 0;
        for (; i < loan.debt.length;) {
            uint256 interest =
                _getInterest(details.debtAmount, details.rate, loan.start, block.timestamp, details.decimals);

            if (carryConsideration.length > 0) {
                carryConsideration[i + 1] = SpentItem({
                    itemType: ItemType.ERC20,
                    identifier: 0,
                    amount: (interest * details.carryRate) / 10 ** details.decimals,
                    token: details.token
                });
                repayConsideration[i + 1] = SpentItem({
                    itemType: ItemType.ERC20,
                    identifier: 0,
                    amount: details.debtAmount + interest - carryConsideration[i].amount,
                    token: details.token
                });
            } else {
                repayConsideration[i + 1] = SpentItem({
                    itemType: ItemType.ERC20,
                    identifier: 0,
                    amount: details.debtAmount + interest,
                    token: details.token
                });
            }
            unchecked {
                ++i;
            }
        }
    }

    function validate(Starport.Loan calldata loan) external view virtual override returns (bytes4) {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));
        return (details.decimals > 0) ? Validation.validate.selector : bytes4(0xFFFFFFFF);
    }

    function getInterest(Starport.Loan calldata loan, uint256 end) public pure returns (uint256) {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));
        uint256 delta_t = end - loan.start;
        return calculateInterest(delta_t, details.debtAmount, details.rate, details.decimals);
    }

    function _getInterest(uint256 amount, uint256 rate, uint256 start, uint256 end, uint256 decimals)
        public
        pure
        returns (uint256)
    {
        uint256 delta_t = end - start;
        return calculateInterest(delta_t, amount, rate, decimals);
    }

    function calculateInterest(uint256 delta_t, uint256 amount, uint256 rate, uint256 decimals)
        public
        pure
        returns (uint256)
    {
        return StarportLib.calculateSimpleInterest(delta_t, amount, rate, decimals);
    }

    function getRefinanceConsideration(Starport.Loan calldata loan, bytes memory newPricingData, address fulfiller)
        external
        view
        virtual
        override
        returns (
            SpentItem[] memory repayConsideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalConsideration
        )
    {
        revert NoRefinance();
    }
}

contract MockOriginator is StrategistOriginator, TokenReceiverInterface {
    constructor(Starport SP_, address strategist_, uint256 fee_)
        StrategistOriginator(SP_, strategist_, fee_, msg.sender)
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

    function terms(bytes calldata) public view returns (Starport.Terms memory) {
        return Starport.Terms({
            status: address(0),
            settlement: address(0),
            pricing: address(0),
            pricingData: new bytes(0),
            settlementData: new bytes(0),
            statusData: new bytes(0)
        });
    }

    function originate(Request calldata params) external virtual override {
        StrategistOriginator.Details memory details = abi.decode(params.details, (StrategistOriginator.Details));
        _validateOffer(params, details);

        Starport.Loan memory loan = Starport.Loan({
            start: uint256(0), // are set in the loan manager
            originator: address(0), // are set in the loan manager
            custodian: details.custodian,
            issuer: details.issuer,
            borrower: params.borrower,
            collateral: params.collateral,
            debt: params.debt,
            terms: details.offer.terms
        });

        CaveatEnforcer.SignedCaveats memory le;
        SP.originate(new AdditionalTransfer[](0), params.borrowerCaveat, le, loan);
    }

    receive() external payable {}
}

contract MockCustodian is Custodian {
    bool returnValidSelector = false;

    constructor(Starport SP_, address seaport) Custodian(SP_, seaport) {}

    function setReturnValidSelector(bool returnValidSelector_) public {
        returnValidSelector = returnValidSelector_;
    }

    function custody(Starport.Loan memory loan) external virtual override onlyStarport returns (bytes4 selector) {
        if (returnValidSelector) {
            selector = Custodian.custody.selector;
        }
    }
}

contract TestStarport is StarportTest, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;

    Starport.Loan public activeLoan;

    using {StarportLib.getId} for Starport.Loan;

    uint256 public borrowAmount = 100;
    MockCustodian public mockCustodian;

    event CaveatNonceIncremented(address owner, uint256 newNonce);
    event CaveatSaltInvalidated(address owner, bytes32 salt);

    event Open(uint256 LoanId, Starport.Loan loan);

    function setUp() public virtual override {
        super.setUp();
        mockCustodian = new MockCustodian(SP, address(seaport));
        Starport.Loan memory loan = newLoanWithDefaultTerms();
        Custodian(custodian).mint(loan);

        loan.toStorage(activeLoan);
    }

    function testIncrementCaveatNonce() public {
        vm.roll(5);
        uint256 newNonce = SP.caveatNonces(address(this)) + uint256(blockhash(block.number - 1) << 0x80);
        vm.expectEmit();
        emit CaveatNonceIncremented(address(this), newNonce);
        SP.incrementCaveatNonce();
    }

    function testInvalidateCaveatSalt() public {
        bytes32 salt = bytes32(uint256(2));
        vm.expectEmit();
        emit CaveatSaltInvalidated(address(this), salt);
        SP.invalidateCaveatSalt(salt);
    }

    function testCannotSettleUnlessValidCustodian() public {
        vm.expectRevert(abi.encodeWithSelector(Starport.NotLoanCustodian.selector));
        SP.settle(activeLoan);
    }

    function testCannotSettleInvalidLoan() public {
        activeLoan.borrower = address(0);
        vm.prank(activeLoan.custodian);
        vm.expectRevert(abi.encodeWithSelector(Starport.InvalidLoan.selector));
        SP.settle(activeLoan);
    }

    event Paused();
    event Unpaused();

    function testPause() public {
        vm.expectEmit(address(SP));
        emit Paused();
        SP.pause();
        assert(SP.paused());
    }

    function testUnpause() public {
        SP.pause();
        vm.expectEmit(address(SP));
        emit Unpaused();
        SP.unpause();
        assert(!SP.paused());
    }

    function testApplyRefinanceConsiderationToLoanMalformed() public {
        vm.expectRevert(Starport.MalformedRefinance.selector);
        SP.applyRefinanceConsiderationToLoan(activeLoan, new SpentItem[](0), new SpentItem[](0), "");

        SpentItem[] memory dummy = new SpentItem[](1);
        dummy[0] = SpentItem({token: address(0), amount: 0, identifier: 0, itemType: ItemType.ERC20});
        SpentItem[] memory dummyCarry = new SpentItem[](2);
        dummyCarry[0] = SpentItem({token: address(0), amount: 0, identifier: 0, itemType: ItemType.ERC20});
        dummyCarry[1] = SpentItem({token: address(0), amount: 0, identifier: 0, itemType: ItemType.ERC20});
        vm.expectRevert(Starport.MalformedRefinance.selector);
        SP.applyRefinanceConsiderationToLoan(activeLoan, dummy, dummyCarry, "");
        vm.expectRevert(Starport.MalformedRefinance.selector);
        SP.applyRefinanceConsiderationToLoan(activeLoan, dummyCarry, new SpentItem[](0), "");
    }

    function testInitializedFlagSetProperly() public {
        activeLoan.borrower = address(0);
        assert(SP.inactive(activeLoan.getId()));
    }

    function testActive() public {
        assert(SP.active(activeLoan.getId()));
    }

    function testNonDefaultCustodianCustodyCallFails() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.custodian = address(mockCustodian);
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(Starport.InvalidCustodian.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testCannotOriginateWhilePaused() public {
        SP.pause();
        Starport.Loan memory loan = generateDefaultLoanTerms();
        vm.expectRevert(abi.encodeWithSelector(PausableNonReentrant.IsPaused.selector));
        SP.originate(new AdditionalTransfer[](0), _emptyCaveat(), _emptyCaveat(), loan);
    }

    event log_loan(Starport.Loan loan);

    function testNonDefaultCustodianCustodyCallSuccess() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        //        Starport.Loan memory copy = loanCopy(loan);
        loan.collateral[0].identifier = uint256(2);
        loan.custodian = address(mockCustodian);
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        //        copy.start = block.timestamp;
        //        copy.originator = loan.borrower;
        //        vm.mockCall(
        //            address(mockCustodian),
        //            abi.encodeWithSelector(MockCustodian.custody.selector, copy),
        //            abi.encode(MockCustodian.custody.selector)
        //        );
        //todo: no idea why the mock doesnt work
        mockCustodian.setReturnValidSelector(true);
        vm.startPrank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidTransferLengthDebt() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        delete loan.debt;
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidTransferLength.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidAmountCollateral() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.collateral[0].amount = 0;
        loan.debt[0].amount = 0;
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemAmount.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidItemType() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].itemType = ItemType.ERC721_WITH_CRITERIA;
        loan.debt[0].token = address(0);
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);

        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemType.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testTokenNoCodeDebt() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.debt[0].token = address(0);
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);

        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemTokenNoCode.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testTokenNoCodeCollateral() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].token = address(0);
        loan.collateral[0].identifier = uint256(2);
        loan.collateral[0].amount = 0;
        loan.debt[0].amount = 0;
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });

        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemTokenNoCode.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidAmountCollateral721() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.collateral[0].identifier = uint256(2);
        loan.collateral[0].amount = uint256(2);
        loan.debt[0].amount = 0;
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidItemAmount.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testInvalidTransferLengthCollateral() public {
        CaveatEnforcer.SignedCaveats memory borrowerCaveat;

        Starport.Loan memory loan = generateDefaultLoanTerms();
        delete loan.collateral;
        CaveatEnforcer.SignedCaveats memory lenderCaveat = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(StarportLib.InvalidTransferLength.selector));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, loan);
        vm.stopPrank();
    }

    function testDefaultFeeRake() public {
        assertEq(SP.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        SP.setFeeData(feeReceiver, 1e17); //10% fees

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC721SpentItem(erc721s[0], uint256(2)), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        Starport.Loan memory loan =
            newLoan(originationDetails, bytes32(bytes32(msg.sig)), bytes32(bytes32(msg.sig)), lender.addr);
        assertEq(erc20s[0].balanceOf(feeReceiver), loan.debt[0].amount * 1e17 / 1e18, "fee receiver not paid properly");
    }

    function testDefaultFeeRakeExoticDebt() public {
        assertEq(SP.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        SP.setFeeData(feeReceiver, 1e17); //10% fees

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC721SpentItem(erc721s[0], uint256(2)), _getERC1155SpentItem(erc1155s[1]), lender.addr
        );

        Starport.Loan memory loan =
            newLoan(originationDetails, bytes32(bytes32(msg.sig)), bytes32(bytes32(msg.sig)), lender.addr);
        assertEq(erc20s[0].balanceOf(feeReceiver), 0, "fee receiver not paid properly");
    }

    function testOverrideFeeRake() public {
        assertEq(SP.defaultFeeRake(), 0);
        address feeReceiver = address(20);
        SP.setFeeData(feeReceiver, 1e17); //10% fees
        SP.setFeeOverride(address(erc20s[0]), 0, true); //0% fees

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC721SpentItem(erc721s[0], uint256(2)), _getERC20SpentItem(erc20s[0], borrowAmount), lender.addr
        );

        newLoan(originationDetails, bytes32(bytes32(msg.sig)), bytes32(bytes32(msg.sig)), lender.addr);
        assertEq(erc20s[0].balanceOf(feeReceiver), 0, "fee receiver paid improperly");
    }

    // needs modification to work with the new origination flow (unsure if it needs to be elimianted all together)
    function testCaveatEnforcerRevert() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        CaveatEnforcer.SignedCaveats memory borrowerEnforcer;
        CaveatEnforcer.SignedCaveats memory lenderEnforcer = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        loan.custodian = address(mockCustodian);
        vm.expectRevert();
        SP.originate(new AdditionalTransfer[](0), borrowerEnforcer, lenderEnforcer, loan);
    }

    function testExoticDebtWithNoCaveatsNotAsBorrower() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        SpentItem[] memory exoticDebt = new SpentItem[](2);
        exoticDebt[0] = SpentItem({token: address(erc1155s[1]), amount: 1, identifier: 1, itemType: ItemType.ERC1155});
        exoticDebt[1] = SpentItem({token: address(erc721s[2]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        loan.debt = exoticDebt;
        loan.collateral[0] =
            SpentItem({token: address(erc721s[0]), amount: 1, identifier: 2, itemType: ItemType.ERC721});
        CaveatEnforcer.SignedCaveats memory borrowerEnforcer;
        CaveatEnforcer.SignedCaveats memory lenderEnforcer = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        Starport.Loan memory loanCopy = abi.decode(abi.encode(loan), (Starport.Loan));
        loanCopy.start = block.timestamp;
        loanCopy.originator = address(loan.borrower);
        vm.expectEmit();
        emit Open(loanCopy.getId(), loanCopy);
        vm.prank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), borrowerEnforcer, lenderEnforcer, loan);
    }

    function testExoticDebtWithCustomPricingAndRepayment() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        MockExoticPricing mockPricing = new MockExoticPricing(SP);

        loan.terms.pricing = address(mockPricing);
        loan.terms.pricingData = abi.encode(
            MockExoticPricing.Details({
                token: address(erc20s[0]),
                debtAmount: 100,
                rate: 100,
                carryRate: 100,
                decimals: 18
            })
        );

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc721s[2]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        loan.debt = exoticDebt;
        loan.collateral[0] =
            SpentItem({token: address(erc721s[0]), amount: 1, identifier: 2, itemType: ItemType.ERC721});
        CaveatEnforcer.SignedCaveats memory borrowerEnforcer;
        CaveatEnforcer.SignedCaveats memory lenderEnforcer = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        Starport.Loan memory loanCopy = abi.decode(abi.encode(loan), (Starport.Loan));
        loanCopy.start = block.timestamp;
        loanCopy.originator = address(loan.borrower);
        vm.expectEmit();
        emit Open(loanCopy.getId(), loanCopy);
        vm.prank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), borrowerEnforcer, lenderEnforcer, loan);
        loan.start = block.timestamp;
        loan.originator = address(loan.borrower);

        skip(100);

        _executeRepayLoan(loan, loan.borrower);
    }

    function testExoticDebtWithCustomPricingAndSettlement() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        MockExoticPricing mockPricing = new MockExoticPricing(SP);
        MockFixedTermDutchAuctionSettlement mockSettlement =
            new MockFixedTermDutchAuctionSettlement(SP, address(erc20s[0]));
        loan.terms.settlement = address(mockSettlement);
        loan.terms.pricing = address(mockPricing);
        loan.terms.pricingData = abi.encode(
            MockExoticPricing.Details({
                token: address(erc20s[0]),
                debtAmount: 100,
                rate: 100,
                carryRate: 100,
                decimals: 18
            })
        );
        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc721s[2]), amount: 1, identifier: 1, itemType: ItemType.ERC721});

        loan.debt = exoticDebt;
        loan.collateral[0] =
            SpentItem({token: address(erc721s[0]), amount: 1, identifier: 2, itemType: ItemType.ERC721});
        CaveatEnforcer.SignedCaveats memory borrowerEnforcer;
        CaveatEnforcer.SignedCaveats memory lenderEnforcer = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        Starport.Loan memory loanCopy = abi.decode(abi.encode(loan), (Starport.Loan));
        loanCopy.start = block.timestamp;
        loanCopy.originator = address(loan.borrower);
        vm.expectEmit();
        emit Open(loanCopy.getId(), loanCopy);
        vm.prank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), borrowerEnforcer, lenderEnforcer, loan);
        loan.start = block.timestamp;
        loan.originator = address(loan.borrower);

        skip(abi.decode(loan.terms.statusData, (FixedTermStatus.Details)).loanDuration + 1);

        _settleLoan(loan, loan.borrower);
    }

    function testNonPayableFunctions() public {
        CaveatEnforcer.SignedCaveats memory be;
        vm.expectRevert();
        payable(address(SP)).call{value: 1 ether}(
            abi.encodeWithSelector(
                Starport.originate.selector, new AdditionalTransfer[](0), be, be, generateDefaultLoanTerms()
            )
        );
        vm.expectRevert();
        payable(address(SP)).call{value: 1 ether}(
            abi.encodeWithSelector(Starport.refinance.selector, address(0), be, generateDefaultLoanTerms(), "")
        );
    }

    //cavets prevent this flow i think, as borrower needs 2 lender caveats to
    function testCannotIssueSameLoanTwice() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc20s[0]), amount: 100, identifier: 0, itemType: ItemType.ERC20});

        loan.debt = exoticDebt;
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc20s[0]), amount: 20, identifier: 0, itemType: ItemType.ERC20});
        loan.collateral = maxSpent;
        CaveatEnforcer.SignedCaveats memory be;
        CaveatEnforcer.SignedCaveats memory le1 = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        CaveatEnforcer.SignedCaveats memory le2 = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(uint256(1)),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        vm.prank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), be, le1, loan);
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        vm.expectRevert(abi.encodeWithSelector(Starport.LoanExists.selector));
        vm.prank(loan.borrower);
        SP.originate(new AdditionalTransfer[](0), be, le2, loan);
    }

    function testAdditionalTransfers() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc20s[0]), amount: 100, identifier: 0, itemType: ItemType.ERC20});

        loan.debt = exoticDebt;
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc20s[0]), amount: 20, identifier: 0, itemType: ItemType.ERC20});
        loan.collateral = maxSpent;
        CaveatEnforcer.SignedCaveats memory be;
        CaveatEnforcer.SignedCaveats memory le1 = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        AdditionalTransfer[] memory additionalTransfers = new AdditionalTransfer[](1);
        additionalTransfers[0] = AdditionalTransfer({
            itemType: ItemType.ERC20,
            token: address(erc20s[0]),
            from: address(loan.borrower),
            to: address(address(20)),
            identifier: 0,
            amount: 20
        });
        vm.prank(loan.borrower);
        ERC20(address(erc20s[0])).approve(address(SP), type(uint256).max);
        vm.prank(loan.borrower);
        SP.originate(additionalTransfers, be, le1, loan);
        assert(erc20s[0].balanceOf(address(20)) == 20);
        assert(erc20s[0].balanceOf(address(loan.custodian)) == 20);
    }

    function testInvalidAdditionalTransfersOriginate() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc20s[0]), amount: 100, identifier: 0, itemType: ItemType.ERC20});

        loan.debt = exoticDebt;
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc20s[0]), amount: 20, identifier: 0, itemType: ItemType.ERC20});
        loan.collateral = maxSpent;

        CaveatEnforcer.SignedCaveats memory le1 = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        AdditionalTransfer[] memory additionalTransfers = new AdditionalTransfer[](1);
        additionalTransfers[0] = AdditionalTransfer({
            itemType: ItemType.ERC20,
            token: address(erc20s[0]),
            from: address(20),
            to: address(loan.borrower),
            identifier: 0,
            amount: 20
        });
        vm.expectRevert(abi.encodeWithSelector(Starport.UnauthorizedAdditionalTransferIncluded.selector));
        vm.prank(loan.borrower);
        SP.originate(additionalTransfers, _emptyCaveat(), le1, loan);
    }

    function testAdditionalTransfersOriginate() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        SpentItem[] memory exoticDebt = new SpentItem[](1);
        exoticDebt[0] = SpentItem({token: address(erc20s[0]), amount: 100, identifier: 0, itemType: ItemType.ERC20});

        loan.debt = exoticDebt;
        SpentItem[] memory maxSpent = new SpentItem[](1);
        maxSpent[0] = SpentItem({token: address(erc20s[0]), amount: 20, identifier: 0, itemType: ItemType.ERC20});
        loan.collateral = maxSpent;

        CaveatEnforcer.SignedCaveats memory le1 = getLenderSignedCaveat({
            details: LenderEnforcer.Details({loan: loan}),
            signer: lender,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);
        AdditionalTransfer[] memory additionalTransfers = new AdditionalTransfer[](1);
        additionalTransfers[0] = AdditionalTransfer({
            itemType: ItemType.ERC20,
            token: address(erc20s[0]),
            from: address(loan.borrower),
            to: address(loan.issuer),
            identifier: 0,
            amount: 20
        });
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(address(loan.issuer));
        vm.prank(loan.borrower);
        SP.originate(additionalTransfers, _emptyCaveat(), le1, loan);
        assert(erc20s[0].balanceOf(address(loan.issuer)) == lenderBalanceBefore - loan.debt[0].amount + 20);
    }

    function testAdditionalTransfersRefinance() public {
        BasePricing.Details memory currentPricing = abi.decode(activeLoan.terms.pricingData, (BasePricing.Details));

        BasePricing.Details memory newPricingDetails =
            BasePricing.Details({rate: currentPricing.rate - 1, carryRate: currentPricing.carryRate, decimals: 18});
        bytes memory newPricingData = abi.encode(newPricingDetails);
        (SpentItem[] memory refinanceConsideration, SpentItem[] memory carryConsideration,) =
            Pricing(activeLoan.terms.pricing).getRefinanceConsideration(activeLoan, newPricingData, lender.addr);
        AdditionalTransfer[] memory at = new AdditionalTransfer[](1);
        at[0] = AdditionalTransfer({
            itemType: ItemType.ERC20,
            token: address(erc20s[0]),
            from: address(activeLoan.issuer),
            to: address(activeLoan.borrower),
            identifier: 0,
            amount: 20
        });
        vm.mockCall(
            activeLoan.terms.pricing,
            abi.encodeWithSelector(Pricing.getRefinanceConsideration.selector, activeLoan, newPricingData, lender.addr),
            abi.encode(refinanceConsideration, carryConsideration, at)
        );
        skip(1);
        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(address(activeLoan.borrower));
        vm.startPrank(lender.addr);
        SP.refinance(lender.addr, _emptyCaveat(), activeLoan, newPricingData);
        assert(erc20s[0].balanceOf(address(activeLoan.borrower)) == borrowerBalanceBefore + 20);
    }

    function testRefinancePostRepaymentFails() public {
        BasePricing.Details memory currentPricing = abi.decode(activeLoan.terms.pricingData, (BasePricing.Details));

        BasePricing.Details memory newPricingDetails =
            BasePricing.Details({rate: currentPricing.rate - 1, carryRate: currentPricing.carryRate, decimals: 18});
        bytes memory newPricingData = abi.encode(newPricingDetails);

        vm.mockCall(
            activeLoan.terms.settlement,
            abi.encodeWithSelector(Settlement.postRepayment.selector, activeLoan, lender.addr),
            abi.encode(bytes4(0))
        );
        skip(1);
        vm.expectRevert(abi.encodeWithSelector(Starport.InvalidPostRepayment.selector));
        vm.startPrank(lender.addr);
        SP.refinance(lender.addr, _emptyCaveat(), activeLoan, newPricingData);
    }

    function testInvalidAdditionalTransfersRefinance() public {
        BasePricing.Details memory currentPricing = abi.decode(activeLoan.terms.pricingData, (BasePricing.Details));

        BasePricing.Details memory newPricingDetails =
            BasePricing.Details({rate: currentPricing.rate - 1, carryRate: currentPricing.carryRate, decimals: 18});
        bytes memory newPricingData = abi.encode(newPricingDetails);
        (SpentItem[] memory refinanceConsideration, SpentItem[] memory carryConsideration,) =
            Pricing(activeLoan.terms.pricing).getRefinanceConsideration(activeLoan, newPricingData, lender.addr);
        AdditionalTransfer[] memory at = new AdditionalTransfer[](1);
        at[0] = AdditionalTransfer({
            itemType: ItemType.ERC20,
            token: address(erc20s[0]),
            from: address(activeLoan.borrower),
            to: address(activeLoan.issuer),
            identifier: 0,
            amount: 20
        });
        vm.mockCall(
            activeLoan.terms.pricing,
            abi.encodeWithSelector(Pricing.getRefinanceConsideration.selector, activeLoan, newPricingData, lender.addr),
            abi.encode(refinanceConsideration, carryConsideration, at)
        );
        skip(1);
        vm.startPrank(lender.addr);
        vm.expectRevert(abi.encodeWithSelector(Starport.UnauthorizedAdditionalTransferIncluded.selector));
        SP.refinance(lender.addr, _emptyCaveat(), activeLoan, newPricingData);
    }
}
