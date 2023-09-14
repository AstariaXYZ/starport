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

import {ConduitHelper} from "src/ConduitHelper.sol";
import "forge-std/console.sol";

contract DutchAuctionHandler is
  SettlementHandler,
  AmountDeriver,
  ConduitHelper
{
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

    (
      ReceivedItem[] memory paymentConsiderations,
      ReceivedItem[] memory carryFeeConsideration
    ) = Pricing(loan.terms.pricing).getPaymentConsideration(loan);

    consideration = new ReceivedItem[](
      paymentConsiderations.length + carryFeeConsideration.length
    );

    //loop the payment considerations and add them to the consideration array

    uint256 i = 0;
    for (; i < paymentConsiderations.length; ) {
      consideration[i] = paymentConsiderations[i];
      unchecked {
        ++i;
      }
    }
    uint256 j = 0;
    i = paymentConsiderations.length;
    //loop fee considerations and add them to the consideration array
    for (; j < carryFeeConsideration.length; ) {
      if (carryFeeConsideration[j].amount > 0) {
        consideration[i + j] = carryFeeConsideration[j];
      }
      unchecked {
        ++j;
      }
    }
    consideration = _removeZeroAmounts(consideration);
  }

  function validate(
    LoanManager.Loan calldata loan
  ) external view override returns (bool) {
    Details memory details = abi.decode(loan.terms.handlerData, (Details));
    return details.startingPrice > details.endingPrice;
  }
}
