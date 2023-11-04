pragma solidity ^0.8.17;

import "starport-test/AstariaV1Test.sol";
import {StarportLib, Actions} from "starport-core/lib/StarportLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import "forge-std/console2.sol";

contract TestAstariaV1Status is AstariaV1Test, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    using {StarportLib.getId} for Starport.Loan;

    event Recalled(uint256 loandId, address recaller, uint256 end);
    event Withdraw(uint256 loanId, address withdrawer);

    function testIsActive() public {
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
        uint256 loanId = loan.getId();
        assert(AstariaV1Status(loan.terms.status).isActive(loan));
    }

    function testIsRecalledInsideWindow() public {
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
        uint256 loanId = loan.getId();

        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.status, 10e18);

        skip(details.honeymoon);
        vm.expectEmit();
        emit Recalled(loanId, address(this), block.timestamp + details.recallWindow);
        AstariaV1Status(loan.terms.status).recall(loan);
        (address recaller, uint64 recallStart) = AstariaV1Status(loan.terms.status).recalls(loanId);
        skip(details.recallWindow - 1);
        assert(AstariaV1Status(loan.terms.status).isActive(loan));
        assert(AstariaV1Status(loan.terms.status).isRecalled(loan));
    }

    function testRecallAndRefinanceInsideWindow() public {
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
        uint256 loanId = loan.getId();

        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.status, 10e18);

        skip(details.honeymoon);
        vm.expectEmit();
        emit Recalled(loanId, address(this), block.timestamp + details.recallWindow);
        AstariaV1Status(loan.terms.status).recall(loan);
        (address recaller, uint64 recallStart) = AstariaV1Status(loan.terms.status).recalls(loanId);
        skip(details.recallWindow - 1);
        address newLender = address(55);

        BasePricing.Details memory newPricingData = abi.decode(defaultPricingData, (BasePricing.Details));
        newPricingData.rate = newPricingData.rate * 2;

        vm.startPrank(newLender);
        erc20s[0].mint(newLender, 10e18);
        erc20s[0].approve(address(SP), 10e18);
        SP.refinance(newLender, _emptyCaveat(), loan, abi.encode(newPricingData));
        assert(erc20s[0].balanceOf(address(loan.terms.status)) == 0);
    }

    function testInvalidRecallLoanDoesNotExist() public {
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
        uint256 loanId = loan.getId();

        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.status, 10e18);

        skip(details.honeymoon);
        vm.mockCall(address(SP), abi.encodeWithSelector(SP.inactive.selector, loan.getId()), abi.encode(true));
        vm.expectRevert(abi.encodeWithSelector(BaseRecall.LoanDoesNotExist.selector));
        AstariaV1Status(loan.terms.status).recall(loan);
    }

    function testInvalidRecallInvalidStakeType() public {
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
        uint256 loanId = loan.getId();

        loan.debt[0].itemType = ItemType.ERC721;
        loan.debt[0].amount = 1;
        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        skip(details.honeymoon);
        vm.mockCall(address(SP), abi.encodeWithSelector(SP.inactive.selector, loan.getId()), abi.encode(false));
        AstariaV1Status(loan.terms.status).recall(loan);
        skip(details.recallWindow);
        vm.mockCall(address(SP), abi.encodeWithSelector(SP.active.selector, loan.getId()), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(BaseRecall.InvalidItemType.selector));
        AstariaV1Status(loan.terms.status).withdraw(loan, payable(address(this)));
    }

    function testCannotRecallTwice() public {
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
        uint256 loanId = loan.getId();

        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.status, 10e18);

        skip(details.honeymoon);
        AstariaV1Status(loan.terms.status).recall(loan);
        vm.expectRevert(abi.encodeWithSelector(BaseRecall.RecallAlreadyExists.selector));
        AstariaV1Status(loan.terms.status).recall(loan);
    }

    function testIsRecalledOutsideWindow() public {
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
        uint256 loanId = loan.getId();
        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.status, 10e18);

        skip(details.honeymoon);
        AstariaV1Status(loan.terms.status).recall(loan);
        (address recaller, uint64 recallStart) = AstariaV1Status(loan.terms.status).recalls(loanId);
        skip(details.recallWindow + 1);
        assert(!AstariaV1Status(loan.terms.status).isActive(loan));
        assert(!AstariaV1Status(loan.terms.status).isRecalled(loan));
    }

    function testGenerateRecallConsideration() public {
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
        uint256 loanId = loan.getId();

        BaseRecall.Details memory recallDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));
        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        //compute interest across a band from 0 to recallStakeDuration instead of from loan.start to end
        uint256 recallStake = BasePricing(loan.terms.pricing).getInterest(
            loan,
            pricingDetails.rate,
            0,
            recallDetails.recallStakeDuration,
            0 //index of the loan
        );
        uint256 proportion = 1e18;
        AdditionalTransfer[] memory recallConsideration = AstariaV1Status(loan.terms.status).generateRecallConsideration(
            loan, proportion, payable(address(this)), payable(loan.issuer)
        );
        assertEq(recallConsideration[0].token, address(erc20s[0]));
        assertEq(recallConsideration[0].amount, recallStake);
        assert(recallConsideration.length == 1);
        proportion = 5e17;
        recallConsideration = AstariaV1Status(loan.terms.status).generateRecallConsideration(
            loan, proportion, payable(address(this)), payable(loan.issuer)
        );
        assertEq(recallConsideration[0].token, address(erc20s[0]));
        assertEq(recallConsideration[0].amount, recallStake / 2);
        assert(recallConsideration.length == 1);
    }

    function testRecallRateEmptyRecall() public {
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
        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));
        uint256 recallRate = AstariaV1Status(loan.terms.status).getRecallRate(loan);
        uint256 computedRecallRate =
            hookDetails.recallMax.mulWad((block.timestamp - 0).divWad(hookDetails.recallWindow));
        assertEq(recallRate, computedRecallRate);
    }

    function testRecallRateActiveRecall() public {
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
        uint256 loanId = loan.getId();
        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.status, 10e18);

        skip(hookDetails.honeymoon);
        AstariaV1Status(loan.terms.status).recall(loan);
        (address recaller, uint64 recallStart) = AstariaV1Status(loan.terms.status).recalls(loanId);
        uint256 recallRate = AstariaV1Status(loan.terms.status).getRecallRate(loan);
        uint256 computedRecallRate =
            hookDetails.recallMax.mulWad((block.timestamp - recallStart).divWad(hookDetails.recallWindow));
        assertEq(recallRate, computedRecallRate);
    }

    function testCannotWithdrawWithdrawDoesNotExist() public {
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
        vm.mockCall(address(SP), abi.encodeWithSelector(SP.active.selector, loan.getId()), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(BaseRecall.WithdrawDoesNotExist.selector));
        AstariaV1Status(loan.terms.status).withdraw(loan, payable(address(this)));
    }

    function testCannotWithdrawLoanHasNotBeenRefinanced() public {
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
        vm.expectRevert(abi.encodeWithSelector(BaseRecall.LoanHasNotBeenRefinanced.selector));
        AstariaV1Status(loan.terms.status).withdraw(loan, payable(address(this)));
    }
    //    //TODO: this needs to be done because withdraw is being looked at
    //    function testRecallWithdraw() public {
    //        Starport.Terms memory terms = Starport.Terms({
    //            status: address(hook),
    //            settlement: address(settlement),
    //            pricing: address(pricing),
    //            pricingData: defaultPricingData,
    //            settlementData: defaultSettlementData,
    //            statusData: defaultStatusData
    //        });
    //        Starport.Loan memory loan =
    //            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
    //        uint256 loanId = loan.getId();
    //        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));
    //
    //        erc20s[0].mint(address(this), 10e18);
    //        erc20s[0].approve(loan.terms.status, 10e18);
    //
    //        skip(hookDetails.honeymoon);
    //        AstariaV1Status(loan.terms.status).recall(loan);
    //
    //        vm.mockCall(address(SP), abi.encodeWithSelector(SP.inactive.selector, loanId), abi.encode(true));
    //    }
}
