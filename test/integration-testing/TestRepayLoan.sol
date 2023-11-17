pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {SimpleInterestPricing} from "starport-core/pricing/SimpleInterestPricing.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {ZoneInteractionErrors} from "seaport-types/src/interfaces/ZoneInteractionErrors.sol";
import "forge-std/console2.sol";

contract TestRepayLoan is StarportTest {
    using FixedPointMathLib for uint256;

    function testRepayLoanBase() public {
        uint256 borrowAmount = 1e18;
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        vm.startPrank(borrower.addr);
        skip(10 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest = SimpleInterestPricing(loan.terms.pricing).calculateInterest(
            10 days, loan.debt[0].amount, details.rate, details.decimals
        );
        erc20s[0].approve(address(consideration), loan.debt[0].amount + interest);
        vm.stopPrank();

        _repayLoan(loan, loan.borrower);
    }

    function testRepayLoanInvalidRepayer() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});

        {
            skip(10 days);
            BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
            uint256 interest = SimpleInterestPricing(loan.terms.pricing).calculateInterest(
                10 days, loan.debt[0].amount, details.rate, details.decimals
            );
            erc20s[0].approve(address(consideration), loan.debt[0].amount + interest);

            uint256 balance = erc20s[0].balanceOf(address(this));
            // ensure the InvalidRepayer has enough to repay
            assertTrue(
                balance > loan.debt[0].amount + interest, "Fulfiller does not have the required repayment balance"
            );
        }

        // test a direct call to the generateOrder method as Seaport because fulfillAdvanceOrder swallows the revert reason
        {
            vm.startPrank(address(consideration));
            vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidRepayer.selector));
            custodian.generateOrder(
                address(this),
                new SpentItem[](0),
                new SpentItem[](0),
                abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
            );
            vm.stopPrank();
        }
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(loan.custodian))
            .previewOrder(
            address(consideration),
            loan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
        );

        OrderParameters memory op = _buildContractOrder(
            address(loan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
        });

        bytes32 orderHash = getOrderHash(address(custodian));

        vm.expectRevert(abi.encodeWithSelector(ZoneInteractionErrors.InvalidContractOrder.selector, orderHash));
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(this)
        });
    }

    function testRepayLoanApprovedRepayer() public {
        uint256 borrowAmount = 1e18;
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        vm.startPrank(borrower.addr);
        skip(10 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest = SimpleInterestPricing(loan.terms.pricing).calculateInterest(
            10 days, loan.debt[0].amount, details.rate, details.decimals
        );
        erc20s[0].approve(address(consideration), loan.debt[0].amount + interest);
        custodian.mintWithApprovalSet(loan, address(this));
        vm.stopPrank();

        _repayLoan(loan, address(this));
    }

    // calling generateOrder on the Custodian to test the onlySeaport modifier
    function testRepayLoanGenerateOrderNotSeaport() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});

        {
            vm.startPrank(fulfiller.addr);
            vm.expectRevert(abi.encodeWithSelector(Custodian.NotSeaport.selector));
            custodian.generateOrder(
                address(this),
                new SpentItem[](0),
                new SpentItem[](0),
                abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
            );
            vm.stopPrank();
        }
    }

    function testRepayLoanInSettlement() public {
        uint256 borrowAmount = 1e18;
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        vm.startPrank(borrower.addr);
        skip(14 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest = SimpleInterestPricing(loan.terms.pricing).calculateInterest(
            10 days, loan.debt[0].amount, details.rate, details.decimals
        );
        erc20s[0].approve(address(consideration), loan.debt[0].amount + interest);
        vm.stopPrank();

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(loan.custodian))
            .previewOrder(
            address(consideration),
            loan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Settlement, loan, ""))
        );

        OrderParameters memory op = _buildContractOrder(
            address(loan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
        });

        // call directly as Seaport ensure InvalidAction is revert reason
        {
            vm.startPrank(address(consideration));
            vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
            custodian.generateOrder(
                loan.borrower,
                new SpentItem[](0),
                new SpentItem[](0),
                abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
            );
            vm.stopPrank();
        }

        bytes32 orderHash = getOrderHash(address(custodian));

        vm.startPrank(loan.borrower);
        vm.expectRevert(abi.encodeWithSelector(ZoneInteractionErrors.InvalidContractOrder.selector, orderHash));
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(this)
        });
        vm.stopPrank();
    }

    function testRepayLoanThatDoesNotExist() public {
        uint256 borrowAmount = 1e18;
        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        vm.startPrank(borrower.addr);
        skip(10 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest = SimpleInterestPricing(loan.terms.pricing).calculateInterest(
            10 days, loan.debt[0].amount, details.rate, details.decimals
        );
        erc20s[0].approve(address(consideration), loan.debt[0].amount + interest);
        vm.stopPrank();

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(loan.custodian))
            .previewOrder(
            address(consideration),
            loan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
        );

        // repaying removes the loanId
        _repayLoan(loan, loan.borrower);

        vm.startPrank(borrower.addr);
        erc721s[0].transferFrom(loan.borrower, loan.custodian, 1);
        vm.stopPrank();

        OrderParameters memory op = _buildContractOrder(
            address(loan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
        });

        // call directly as Seaport ensure InvalidAction is revert reason
        {
            vm.startPrank(address(consideration));
            vm.expectRevert(abi.encodeWithSelector(Starport.InvalidLoan.selector));
            custodian.generateOrder(
                loan.borrower,
                new SpentItem[](0),
                new SpentItem[](0),
                abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
            );
            vm.stopPrank();
        }

        vm.startPrank(loan.borrower);
        erc20s[0].approve(address(consideration), loan.debt[0].amount + interest);
        bytes32 orderHash = getOrderHash(address(custodian));
        vm.expectRevert(abi.encodeWithSelector(ZoneInteractionErrors.InvalidContractOrder.selector, orderHash));
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: loan.borrower
        });
        vm.stopPrank();
    }
}
