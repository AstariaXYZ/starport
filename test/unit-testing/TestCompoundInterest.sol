pragma solidity ^0.8.17;

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {StarportLib, AdditionalTransfer} from "starport-core/lib/StarportLib.sol";
import {Starport} from "starport-core/Starport.sol";
import {AstariaV1LenderEnforcer} from "starport-core/enforcers/AstariaV1LenderEnforcer.sol";

import "starport-test/AstariaV1Test.sol";

contract TestCompoundInterest is AstariaV1Test, AstariaV1LenderEnforcer {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    function testRateMax() public {
        defaultPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: uint256(MAX_RATE) + 1}));
        Starport.Loan memory loan = generateDefaultLoanTerms();
        vm.expectRevert(abi.encodeWithSelector(AstariaV1LenderEnforcer.LoanAmountExceedsMaxRate.selector));
        lenderEnforcer.validate(new AdditionalTransfer[](0), loan, "");
    }

    function testAmountMax() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        loan.debt[0].amount = MAX_AMOUNT + 1;
        vm.expectRevert(abi.encodeWithSelector(AstariaV1LenderEnforcer.LoanAmountExceedsMaxAmount.selector));
        lenderEnforcer.validate(new AdditionalTransfer[](0), loan, "");
    }

    function testRateTooLowZero() public {
        defaultPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: 0}));
        Starport.Loan memory loan = generateDefaultLoanTerms();
        vm.expectRevert(abi.encodeWithSelector(AstariaV1LenderEnforcer.InterestAccrualRoundingMinimum.selector));
        lenderEnforcer.validate(new AdditionalTransfer[](0), loan, "");
    }

    function testRateTooLowOne() public {
        defaultPricingData = abi.encode(BasePricing.Details({carryRate: 0, rate: 1}));
        Starport.Loan memory loan = generateDefaultLoanTerms();
        vm.expectRevert(abi.encodeWithSelector(AstariaV1LenderEnforcer.InterestAccrualRoundingMinimum.selector));
        lenderEnforcer.validate(new AdditionalTransfer[](0), loan, "");
    }
    // function testPrecision() public {
    //   uint256 result = StarportLib.calculateCompoundInterest(uint256(MAX_DURATION), MAX_AMOUNT, uint256(MAX_RATE)) + MAX_AMOUNT;
    //   assertEq(result, MAX_UNSIGNED_INT, "Precision bounds not matching");
    // }
}
