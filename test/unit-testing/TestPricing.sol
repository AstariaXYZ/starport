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
import {
  SimpleInterestPricing
} from "starport-core/pricing/SimpleInterestPricing.sol";

contract TestBasePricing is StarPortTest, DeepEq {
  using Cast for *;
  using FixedPointMathLib for uint256;

  LoanManager.Loan public targetLoan;

  function setUp() public override {
    super.setUp();

    LoanManager.Loan memory loan = _createLoan({
      lender: lender.addr,
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
        hookData: abi.encode(
          FixedTermHook.Details({loanDuration: defaultLoanDuration})
        )
      }),
      collateralItem: ConsiderationItem({
        token: address(erc721s[0]),
        startAmount: 1,
        endAmount: 1,
        identifierOrCriteria: 1,
        itemType: ItemType.ERC721,
        recipient: payable(address(custodian))
      }),
      debtItem: SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: 100,
        identifier: 0
      })
    });

    loan.toStorage(targetLoan);
  }

  function test_getPaymentConsideration() public {
    SimpleInterestPricing simple = new SimpleInterestPricing(LM);

    ReceivedItem[] memory repayConsideration;
    ReceivedItem[] memory repayCarryConsideration;

    (repayConsideration, repayCarryConsideration) = simple
      .getPaymentConsideration(targetLoan);

    // lender
    assertEq(repayConsideration.length, 1);
    assertEq(repayConsideration[0].token, address(erc20s[0]));
    assertEq(repayConsideration[0].amount, 100);
    assertEq(repayConsideration[0].recipient, lender.addr);
    assertEq(repayConsideration[0].identifier, 0);

    // strategist originator
    assertEq(repayCarryConsideration.length, 1);
    assertEq(repayCarryConsideration[0].token, address(erc20s[0]));
    assertEq(repayCarryConsideration[0].amount, 0);
    assertEq(repayCarryConsideration[0].recipient, address(SO));
    assertEq(repayCarryConsideration[0].identifier, 0);
  }

  function test_getOwed() public {
    SimpleInterestPricing simpleInterestPricing = new SimpleInterestPricing(LM);

    assertEq(simpleInterestPricing.getOwed(targetLoan)[0], 100);
  }
}
