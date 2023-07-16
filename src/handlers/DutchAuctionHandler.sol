pragma solidity =0.8.17;

import {
  ItemType,
  OfferItem,
  SpentItem,
  ReceivedItem,
  OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {Originator} from "src/originators/Originator.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {
  LoanManager,
  SettlementHandler
} from "src/handlers/SettlementHandler.sol";

import "forge-std/console.sol";

contract DutchAuctionHandler is SettlementHandler, AmountDeriver {
  constructor(LoanManager LM_) SettlementHandler(LM_) {
    LM = LM_;
  }

  using FixedPointMathLib for uint256;

  error InvalidAmount();

  struct Details {
    uint256 startingPrice;
    uint256 endingPrice;
    uint256 window;
  }

  function getSettlement(
    LoanManager.Loan memory loan
  )
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory consideration, address restricted)
  {
    Details memory details = abi.decode(loan.terms.handlerData, (Details));
    uint256 settlementPrice;

    settlementPrice = _locateCurrentAmount({
      startAmount: details.startingPrice,
      endAmount: details.endingPrice,
      startTime: block.timestamp,
      endTime: block.timestamp + details.window,
      roundUp: true
    });

    ReceivedItem[] memory paymentConsiderations = Pricing(loan.terms.pricing)
      .getPaymentConsideration(loan);
    ReceivedItem[] memory feeConsideration = Originator(loan.originator)
      .getFeeConsideration(loan);
    uint256 considerationLength = paymentConsiderations.length;
    uint256 payment = paymentConsiderations[0].amount;
    uint256 rake = 0;
    if (feeConsideration.length > 0 && feeConsideration[0].amount > 0) {
      rake += feeConsideration[0].amount;
      considerationLength += feeConsideration.length;
      if (
        payment - feeConsideration[0].amount > paymentConsiderations[0].amount
      ) {
        considerationLength += paymentConsiderations.length;
      }
    }

    consideration = new ReceivedItem[](considerationLength);
    //pay the lender
    consideration[0] = ReceivedItem({
      itemType: ItemType.ERC20,
      token: loan.debt[0].token,
      identifier: loan.debt[0].identifier,
      amount: payment - rake,
      recipient: LM.getIssuer(loan)
    });
    //loop the payment considerations and add them to the consideration array
    uint256 i = 0;
    if (paymentConsiderations.length > 1) {
      for (; i < paymentConsiderations.length; ) {
        rake += paymentConsiderations[i].amount;
        consideration[i + 1] = paymentConsiderations[i];
        unchecked {
          ++i;
        }
      }
      i = paymentConsiderations.length;
    }
    uint256 j = 0;
    //loop fee considerations and add them to the consideration array
    for (; j < feeConsideration.length; ) {
      rake += feeConsideration[i].amount;
      consideration[j + i] = feeConsideration[i];
      unchecked {
        j++;
      }
    }
  }

  function validate(
    LoanManager.Loan calldata loan
  ) external view override returns (bool) {
    Details memory details = abi.decode(loan.terms.handlerData, (Details));
    return details.startingPrice > details.endingPrice;
  }
}
