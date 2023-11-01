pragma solidity ^0.8.17;

import "starport-test/StarPortTest.sol";
import {SimpleInterestPricing} from "starport-core/pricing/SimpleInterestPricing.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {ZoneInteractionErrors} from "seaport-types/src/interfaces/ZoneInteractionErrors.sol";
import "forge-std/console2.sol";

contract TestRepayLoan is StarPortTest {
    using FixedPointMathLib for uint256;

    function testRepayLoanBase() public {
        uint256 borrowAmount = 1e18;
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        vm.startPrank(borrower.addr);
        skip(10 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest =
            SimpleInterestPricing(loan.terms.pricing).calculateInterest(10 days, loan.debt[0].amount, details.rate);
        erc20s[0].approve(address(LM.seaport()), loan.debt[0].amount + interest);
        vm.stopPrank();

        _repayLoan(loan, loan.borrower);
    }

    function testRepayLoanInvalidRepayer() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});

        {
            skip(10 days);
            BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
            uint256 interest =
                SimpleInterestPricing(loan.terms.pricing).calculateInterest(10 days, loan.debt[0].amount, details.rate);
            erc20s[0].approve(address(LM.seaport()), loan.debt[0].amount + interest);

            uint256 balance = erc20s[0].balanceOf(address(this));
            // ensure the InvalidRepayer has enough to repay
            assertTrue(
                balance > loan.debt[0].amount + interest, "Fulfiller does not have the required repayment balance"
            );
        }

        // test a direct call to the generateOrder method as Seaport because fulfillAdvanceOrder swallows the revert reason
        {
            vm.startPrank(address(LM.seaport()));
            vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidRepayer.selector));
            custodian.generateOrder(
                address(this), new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Repayment, loan)
            );
            vm.stopPrank();
        }
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(loan.custodian))
            .previewOrder(
            address(LM.seaport()),
            loan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Repayment, loan)
        );

        OrderParameters memory op = _buildContractOrder(
            address(loan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Actions.Repayment, loan)
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
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        vm.startPrank(borrower.addr);
        skip(10 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest =
            SimpleInterestPricing(loan.terms.pricing).calculateInterest(10 days, loan.debt[0].amount, details.rate);
        erc20s[0].approve(address(LM.seaport()), loan.debt[0].amount + interest);
        custodian.setRepayApproval(address(this), true);
        vm.stopPrank();

        _repayLoan(loan, address(this));
    }

    // calling generateOrder on the Custodian to test the onlySeaport modifier
    function testRepayLoanGenerateOrderNotSeaport() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});

        {
            vm.startPrank(fulfiller.addr);
            vm.expectRevert(abi.encodeWithSelector(Custodian.NotSeaport.selector));
            custodian.generateOrder(
                address(this), new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Repayment, loan)
            );
            vm.stopPrank();
        }
    }

    function testRepayLoanInSettlement() public {
        uint256 borrowAmount = 1e18;
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        vm.startPrank(borrower.addr);
        skip(14 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest =
            SimpleInterestPricing(loan.terms.pricing).calculateInterest(10 days, loan.debt[0].amount, details.rate);
        erc20s[0].approve(address(LM.seaport()), loan.debt[0].amount + interest);
        vm.stopPrank();

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(loan.custodian))
            .previewOrder(
            address(LM.seaport()),
            loan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Settlement, loan)
        );

        OrderParameters memory op = _buildContractOrder(
            address(loan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Actions.Repayment, loan)
        });

        // call directly as Seaport ensure InvalidAction is revert reason
        {
            vm.startPrank(address(LM.seaport()));
            vm.expectRevert(abi.encodeWithSelector(Custodian.InvalidAction.selector));
            custodian.generateOrder(
                loan.borrower, new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Repayment, loan)
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
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: borrowAmount, terms: terms});

        vm.startPrank(borrower.addr);
        skip(10 days);
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest =
            SimpleInterestPricing(loan.terms.pricing).calculateInterest(10 days, loan.debt[0].amount, details.rate);
        erc20s[0].approve(address(LM.seaport()), loan.debt[0].amount + interest);
        vm.stopPrank();

        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(loan.custodian))
            .previewOrder(
            address(LM.seaport()),
            loan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Actions.Repayment, loan)
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
            extraData: abi.encode(Actions.Repayment, loan)
        });

        // call directly as Seaport ensure InvalidAction is revert reason
        {
            vm.startPrank(address(LM.seaport()));
            vm.expectRevert(abi.encodeWithSelector(LoanManager.InvalidLoan.selector));
            custodian.generateOrder(
                loan.borrower, new SpentItem[](0), new SpentItem[](0), abi.encode(Actions.Repayment, loan)
            );
            vm.stopPrank();
        }

        vm.startPrank(loan.borrower);
        erc20s[0].approve(address(LM.seaport()), loan.debt[0].amount + interest);
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
