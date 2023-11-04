pragma solidity ^0.8.17;

import "starport-test/AstariaV1Test.sol";
import {StarportLib, Actions} from "starport-core/lib/StarportLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import "forge-std/console2.sol";

contract TestAstariaV1Pricing is AstariaV1Test, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    using {StarportLib.getId} for Starport.Loan;

    function setUp() public override {
        super.setUp();
        defaultPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: uint256(1e16) / (365 * 1 days)}));
        pricing = new AstariaV1Pricing(SP);
    }

    function testGetRefinanceConsiderationInvalidRefinance() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        loan.start = uint256(1);
        loan.originator = address(this);
        vm.warp(2);

        BasePricing.Details memory baseDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        BaseRecall.Details memory statusDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));
        bytes memory newPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: 0}));

        vm.expectRevert(abi.encodeWithSelector(Pricing.InvalidRefinance.selector));
        Pricing(loan.terms.pricing).getRefinanceConsideration(loan, newPricingData, address(this));
    }

    function testGetRefinanceConsiderationInsufficientRefinance() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        loan.start = uint256(1);
        loan.originator = address(this);
        vm.warp(2);

        BasePricing.Details memory baseDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        BaseRecall.Details memory statusDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        //we're lower than the old rate so pay proportions
        uint256 proportion = 1e18;
        vm.mockCall(
            loan.terms.status, abi.encodeWithSelector(AstariaV1Status.isRecalled.selector, loan), abi.encode(true)
        );
        uint256 recallRate = AstariaV1Status(loan.terms.status).getRecallRate(loan);
        bytes memory newPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: recallRate * 2}));

        vm.expectRevert(abi.encodeWithSelector(AstariaV1Pricing.InsufficientRefinance.selector));
        Pricing(loan.terms.pricing).getRefinanceConsideration(loan, newPricingData, address(this));
    }

    function testGetRefinanceConsiderationAsBorrowerZeroRate() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.start = uint256(1);
        loan.originator = address(this);
        vm.warp(2);
        BasePricing.Details memory baseDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        bytes memory newPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: 0}));
        SpentItem[] memory expectedConsideration = new SpentItem[](1);
        expectedConsideration[0] = SpentItem({
            itemType: loan.debt[0].itemType,
            amount: loan.debt[0].amount
                + StarportLib.calculateCompoundInterest(block.timestamp - loan.start, loan.debt[0].amount, baseDetails.rate),
            identifier: loan.debt[0].identifier,
            token: loan.debt[0].token
        });
        SpentItem[] memory expectedCarryConsideration = new SpentItem[](0);
        AdditionalTransfer[] memory expectedAdditionalTransfers = new AdditionalTransfer[](0);

        (
            SpentItem[] memory consideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).getRefinanceConsideration(loan, newPricingData, address(loan.borrower));
        _deepEq(consideration, expectedConsideration);
        _deepEq(carryConsideration, expectedCarryConsideration);
        _deepEq(expectedAdditionalTransfers, additionalTransfers);
    }

    //TODO: is 0 rate allowed?
    function testGetRefinanceConsiderationZeroRate() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        loan.start = uint256(1);
        loan.originator = address(this);
        vm.warp(2);
        BasePricing.Details memory baseDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        bytes memory newPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: 0}));
        BaseRecall.Details memory statusDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));
        uint256 proportion = 1e18 - (baseDetails.rate - 0).divWad(baseDetails.rate);
        vm.mockCall(
            loan.terms.status, abi.encodeWithSelector(AstariaV1Status.isRecalled.selector, loan), abi.encode(true)
        );
        SpentItem[] memory expectedConsideration = new SpentItem[](1);
        expectedConsideration[0] = SpentItem({
            itemType: loan.debt[0].itemType,
            amount: loan.debt[0].amount
                + StarportLib.calculateCompoundInterest(block.timestamp - loan.start, loan.debt[0].amount, baseDetails.rate),
            identifier: loan.debt[0].identifier,
            token: loan.debt[0].token
        });
        SpentItem[] memory expectedCarryConsideration = new SpentItem[](0);
        AdditionalTransfer[] memory expectedAdditionalTransfers = new AdditionalTransfer[](1);
        expectedAdditionalTransfers[0] = AdditionalTransfer({
            identifier: loan.debt[0].identifier,
            itemType: loan.debt[0].itemType,
            token: loan.debt[0].token,
            amount: StarportLib.calculateCompoundInterest(
                statusDetails.recallStakeDuration, loan.debt[0].amount, baseDetails.rate
                ).mulWad(proportion),
            to: loan.issuer,
            from: address(this)
        });

        (
            SpentItem[] memory consideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).getRefinanceConsideration(loan, newPricingData, address(this));
        _deepEq(consideration, expectedConsideration);
        _deepEq(carryConsideration, expectedCarryConsideration);
        _deepEq(expectedAdditionalTransfers, additionalTransfers);
    }

    function testGetRefiannceConsiderationValidEqualRate() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        loan.start = uint256(1);
        loan.originator = address(this);
        vm.warp(2);

        BasePricing.Details memory baseDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        BaseRecall.Details memory statusDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        vm.mockCall(
            loan.terms.status, abi.encodeWithSelector(AstariaV1Status.isRecalled.selector, loan), abi.encode(true)
        );
        skip(statusDetails.recallWindow - 10);
        bytes memory newPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: baseDetails.rate}));
        uint256 proportion = 1e18 - (baseDetails.rate - baseDetails.rate).divWad(baseDetails.rate);

        SpentItem[] memory expectedConsideration = new SpentItem[](1);
        expectedConsideration[0] = SpentItem({
            itemType: loan.debt[0].itemType,
            amount: loan.debt[0].amount
                + StarportLib.calculateCompoundInterest(block.timestamp - loan.start, loan.debt[0].amount, baseDetails.rate),
            identifier: loan.debt[0].identifier,
            token: loan.debt[0].token
        });
        SpentItem[] memory expectedCarryConsideration = new SpentItem[](0);
        AdditionalTransfer[] memory expectedAdditionalTransfers = new AdditionalTransfer[](1);
        expectedAdditionalTransfers[0] = AdditionalTransfer({
            identifier: loan.debt[0].identifier,
            itemType: loan.debt[0].itemType,
            token: loan.debt[0].token,
            amount: StarportLib.calculateCompoundInterest(
                statusDetails.recallStakeDuration, loan.debt[0].amount, baseDetails.rate
                ).mulWad(proportion),
            to: loan.issuer,
            from: address(this)
        });

        vm.mockCall(
            loan.terms.status,
            abi.encodeWithSelector(bytes4(keccak256("recalls(uint256)")), loan.getId()),
            abi.encode(recaller.addr, uint256(0))
        );
        (
            SpentItem[] memory consideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).getRefinanceConsideration(loan, newPricingData, address(this));
        _deepEq(consideration, expectedConsideration);
        _deepEq(carryConsideration, expectedCarryConsideration);
        _deepEq(expectedAdditionalTransfers, additionalTransfers);
    }

    function testGetRefiannceConsiderationValidHigherRate() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        loan.start = uint256(1);
        loan.originator = address(this);
        vm.warp(2);

        BasePricing.Details memory baseDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        BaseRecall.Details memory statusDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        //we're lower than the old rate so pay proportions
        uint256 proportion = 1e18;
        vm.mockCall(
            loan.terms.status, abi.encodeWithSelector(AstariaV1Status.isRecalled.selector, loan), abi.encode(true)
        );
        skip(statusDetails.recallWindow - 10);
        uint256 recallRate = AstariaV1Status(loan.terms.status).getRecallRate(loan);
        bytes memory newPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: recallRate}));

        SpentItem[] memory expectedConsideration = new SpentItem[](1);
        expectedConsideration[0] = SpentItem({
            itemType: loan.debt[0].itemType,
            amount: loan.debt[0].amount
                + StarportLib.calculateCompoundInterest(block.timestamp - loan.start, loan.debt[0].amount, baseDetails.rate),
            identifier: loan.debt[0].identifier,
            token: loan.debt[0].token
        });
        SpentItem[] memory expectedCarryConsideration = new SpentItem[](0);
        AdditionalTransfer[] memory expectedAdditionalTransfers = new AdditionalTransfer[](1);
        expectedAdditionalTransfers[0] = AdditionalTransfer({
            identifier: loan.debt[0].identifier,
            itemType: loan.debt[0].itemType,
            token: loan.debt[0].token,
            amount: StarportLib.calculateCompoundInterest(
                statusDetails.recallStakeDuration, loan.debt[0].amount, baseDetails.rate
                ).mulWad(proportion),
            to: recaller.addr,
            from: address(this)
        });

        vm.mockCall(
            loan.terms.status,
            abi.encodeWithSelector(bytes4(keccak256("recalls(uint256)")), loan.getId()),
            abi.encode(recaller.addr, uint256(0))
        );
        (
            SpentItem[] memory consideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).getRefinanceConsideration(loan, newPricingData, address(this));
        _deepEq(consideration, expectedConsideration);
        _deepEq(carryConsideration, expectedCarryConsideration);
        _deepEq(expectedAdditionalTransfers, additionalTransfers);
    }

    function testGetRefiannceConsiderationValidLowerRate() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        loan.start = uint256(1);
        loan.originator = address(this);
        vm.warp(2);
        uint256 recallRate = AstariaV1Status(loan.terms.status).getRecallRate(loan);

        BasePricing.Details memory baseDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        BaseRecall.Details memory statusDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));
        bytes memory newPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: recallRate}));

        //we're lower than the old rate so pay proportions
        uint256 proportion = 1e18 - (baseDetails.rate - recallRate).divWad(baseDetails.rate);
        vm.mockCall(
            loan.terms.status, abi.encodeWithSelector(AstariaV1Status.isRecalled.selector, loan), abi.encode(true)
        );
        SpentItem[] memory expectedConsideration = new SpentItem[](1);
        expectedConsideration[0] = SpentItem({
            itemType: loan.debt[0].itemType,
            amount: loan.debt[0].amount
                + StarportLib.calculateCompoundInterest(block.timestamp - loan.start, loan.debt[0].amount, baseDetails.rate),
            identifier: loan.debt[0].identifier,
            token: loan.debt[0].token
        });
        SpentItem[] memory expectedCarryConsideration = new SpentItem[](0);
        AdditionalTransfer[] memory expectedAdditionalTransfers = new AdditionalTransfer[](1);
        expectedAdditionalTransfers[0] = AdditionalTransfer({
            identifier: loan.debt[0].identifier,
            itemType: loan.debt[0].itemType,
            token: loan.debt[0].token,
            amount: StarportLib.calculateCompoundInterest(
                statusDetails.recallStakeDuration, loan.debt[0].amount, baseDetails.rate
                ).mulWad(proportion),
            to: loan.issuer,
            from: address(this)
        });

        (
            SpentItem[] memory consideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalTransfers
        ) = Pricing(loan.terms.pricing).getRefinanceConsideration(loan, newPricingData, address(this));
        _deepEq(consideration, expectedConsideration);
        _deepEq(carryConsideration, expectedCarryConsideration);
        _deepEq(expectedAdditionalTransfers, additionalTransfers);
    }
}
