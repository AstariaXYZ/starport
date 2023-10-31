import "forge-std/console2.sol";
import "starport-test/StarPortTest.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {SimpleInterestPricing} from "starport-core/pricing/SimpleInterestPricing.sol";

contract TestBasePricing is StarPortTest, DeepEq {
  using Cast for *;
  using FixedPointMathLib for uint256;

  LoanManager.Loan public targetLoan;

  function setUp() public override {
    super.setUp();

    SpentItem[] memory newCollateral = new SpentItem[](1);
    newCollateral[0] = SpentItem({
      itemType: ItemType.ERC721,
      token: address(erc721s[0]),
      identifier: 1,
      amount: 1
    });

    SpentItem[] memory newDebt = new SpentItem[](1);
    newDebt[0] = SpentItem({
      itemType: ItemType.ERC20,
      token: address(erc20s[0]),
      identifier: 0,
      amount: 100
    });

    LoanManager.Loan memory loan = LoanManager.Loan({
      start: 0,
      custodian: address(custodian),
      borrower: borrower.addr,
      issuer: lender.addr,
      originator: address(0),
      collateral: newCollateral,
      debt: newDebt,
      terms: LoanManager.Terms({
        hook: address(hook),
        handler: address(handler),
        pricing: address(pricing),
        pricingData: abi.encode(
          BasePricing.Details({
            carryRate: (uint256(1e16) * 10),
            rate: (uint256(1e16) * 150) / (365 * 1 days)
          })
        ),
        handlerData: abi.encode(
          DutchAuctionHandler.Details({
            startingPrice: uint256(500 ether),
            endingPrice: 100 wei,
            window: 7 days
          })
        ),
        hookData: abi.encode(FixedTermHook.Details({loanDuration: 14 days}))
      })
    });

    loan.toStorage(targetLoan);
  }

  function test_getPaymentConsideration() public {
    SimpleInterestPricing simplePricing = new SimpleInterestPricing(LM);

    SpentItem[] memory repayConsideration;
    SpentItem[] memory repayCarryConsideration;

    (repayConsideration, repayCarryConsideration) = simplePricing.getPaymentConsideration(
      targetLoan
    );

    // lender
    assertEq(repayConsideration.length, 1);
    assertEq(repayConsideration[0].token, address(erc20s[0]));
    assertEq(repayConsideration[0].amount, 100);
    assertEq(repayConsideration[0].identifier, 0);

    assertEq(repayCarryConsideration.length, 1);
    assertEq(repayCarryConsideration[0].token, address(erc20s[0]));
    assertEq(repayCarryConsideration[0].amount, 0);
    assertEq(repayCarryConsideration[0].identifier, 0);
  }

  // function test_getOwed() public {
  //   SimpleInterestPricing simpleInterestPricing = new SimpleInterestPricing(LM);

  //   assertEq(simpleInterestPricing.getOwed(targetLoan)[0], 100);
  // }
}
