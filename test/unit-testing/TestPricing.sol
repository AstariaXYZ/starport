import "forge-std/console2.sol";
import "starport-test/StarPortTest.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {Starport} from "starport-core/Starport.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {SimpleInterestPricing} from "starport-core/pricing/SimpleInterestPricing.sol";

contract TestSimpleInterestPricing is StarPortTest, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;

    Starport.Loan public targetLoan;

    function setUp() public override {
        super.setUp();

        SpentItem[] memory newCollateral = new SpentItem[](1);
        newCollateral[0] = SpentItem({itemType: ItemType.ERC721, token: address(erc721s[0]), identifier: 1, amount: 1});

        SpentItem[] memory newDebt = new SpentItem[](1);
        newDebt[0] = SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), identifier: 0, amount: 100});

        Starport.Loan memory loan = Starport.Loan({
            start: 0,
            custodian: address(custodian),
            borrower: borrower.addr,
            issuer: lender.addr,
            originator: address(0),
            collateral: newCollateral,
            debt: newDebt,
            terms: Starport.Terms({
                status: address(hook),
                settlement: address(handler),
                pricing: address(pricing),
                pricingData: abi.encode(
                    BasePricing.Details({carryRate: (uint256(1e16) * 10), rate: (uint256(1e16) * 150) / (365 * 1 days)})
                    ),
                settlementData: abi.encode(
                    DutchAuctionHandler.Details({startingPrice: uint256(500 ether), endingPrice: 100 wei, window: 7 days})
                    ),
                statusData: abi.encode(FixedTermHook.Details({loanDuration: 14 days}))
            })
        });

        loan.toStorage(targetLoan);
    }

    function test_getPaymentConsideration() public {
        SimpleInterestPricing simplePricing = new SimpleInterestPricing(SP);

        SpentItem[] memory repayConsideration;
        SpentItem[] memory repayCarryConsideration;

        (repayConsideration, repayCarryConsideration) = simplePricing.getPaymentConsideration(targetLoan);

        assertEq(repayConsideration.length, 1);
        assertEq(repayConsideration[0].token, address(erc20s[0]));
        assertEq(repayConsideration[0].amount, 100);
        assertEq(repayConsideration[0].identifier, 0);

        assertEq(repayCarryConsideration.length, 1);
        assertEq(repayCarryConsideration[0].token, address(erc20s[0]));
        assertEq(repayCarryConsideration[0].amount, 0);
        assertEq(repayCarryConsideration[0].identifier, 0);

        // TODO: move to integration tests?
        vm.warp(60 days);

        (repayConsideration, repayCarryConsideration) = simplePricing.getPaymentConsideration(targetLoan);

        assertEq(repayConsideration.length, 1);
        assertEq(repayConsideration[0].token, address(erc20s[0]));
        assertEq(repayConsideration[0].amount, 122);
        assertEq(repayConsideration[0].identifier, 0);

        assertEq(repayCarryConsideration.length, 1);
        assertEq(repayCarryConsideration[0].token, address(erc20s[0]));
        assertEq(repayCarryConsideration[0].amount, 2);
        assertEq(repayCarryConsideration[0].identifier, 0);
    }

    function test_calculateInterest() public {
        SimpleInterestPricing simplePricing = new SimpleInterestPricing(SP);

        uint256 amount = 100;
        uint256 rate = (uint256(1e16) * 150) / (365 * 1 days);
        uint256 time = 15 days;
        uint256 expectedInterest = 6;

        assertEq(simplePricing.calculateInterest(time, amount, rate), expectedInterest);

        // TODO: should this be fuzz tested?
        assertEq(simplePricing.calculateInterest(time, amount, rate * 2), expectedInterest * 2);
        assertEq(simplePricing.calculateInterest(time, amount * 2, rate), expectedInterest * 2);
        assertEq(simplePricing.calculateInterest(time * 2, amount, rate), expectedInterest * 2);

        vm.expectRevert(stdError.arithmeticError);
        simplePricing.calculateInterest(time - (time * 2), amount, rate);

        vm.expectRevert();
        simplePricing.calculateInterest(time, amount - (amount * 2), rate);

        vm.expectRevert();
        simplePricing.calculateInterest(time, amount, rate - (rate * 2));
    }

    function test_isValidRefinance() public {
        SimpleInterestPricing simplePricing = new SimpleInterestPricing(SP);

        uint256 baseRate = (uint256(1e16) * 150) / (365 * 1 days);

        simplePricing.isValidRefinance(
            targetLoan,
            abi.encode(BasePricing.Details({carryRate: (uint256(1e16) * 10), rate: baseRate / 2})),
            address(0)
        );

        vm.expectRevert(bytes4(keccak256("InvalidRefinance()")));

        simplePricing.isValidRefinance(
            targetLoan,
            abi.encode(BasePricing.Details({carryRate: (uint256(1e16) * 10), rate: baseRate * 2})),
            address(0)
        );
    }
}
