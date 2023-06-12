pragma solidity =0.8.17;

import {
  ItemType,
  OfferItem,
  SpentItem,
  ReceivedItem,
  OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {Originator} from "src/originators/Originator.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {
  LoanManager,
  SettlementHandler
} from "src/handlers/SettlementHandler.sol";

import "forge-std/console.sol";

contract DutchAuctionHandler is SettlementHandler, AmountDeriver {
  using FixedPointMathLib for uint256;
  error InvalidAmount();
  struct Details {
    uint256 startingPrice;
    uint256 endingPrice;
    uint256 window;
  }

  function getSettlement(
    LoanManager.Loan memory loan,
    SpentItem[] calldata minimumReceived,
    uint256 owing,
    address payable lmOwner
  )
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory consideration, address restricted)
  {
    Details memory details = abi.decode(loan.handlerData, (Details));
    uint256 settlementPrice;

    settlementPrice = _locateCurrentAmount({
      startAmount: details.startingPrice,
      endAmount: details.endingPrice,
      startTime: block.timestamp,
      endTime: block.timestamp + details.window,
      roundUp: true
    });


    if (minimumReceived[0].amount < settlementPrice) {
      revert InvalidAmount();
    }

    uint256 fee = settlementPrice.mulWad(
      Originator(loan.originator).strategistFee()
    );
    uint256 considerationLength = 1;
    uint256 payment = minimumReceived[0].amount;
    if (fee > 0) {
      considerationLength = 2;
    }
    if (payment - fee > owing) {
      considerationLength = 3;
    }

    consideration = new ReceivedItem[](considerationLength);

    if (considerationLength > 1) {
      consideration[0] = ReceivedItem({
        itemType: ItemType.ERC20,
        token: loan.debt.token,
        identifier: 0,
        amount: fee,
        recipient: payable(loan.originator)
      });
    }

    //set the borrower slot and lender recipient after as we haven't mutated the loan yet

    if (considerationLength == 3) {
      consideration[2] = ReceivedItem({
        itemType: ItemType.ERC20,
        token: loan.debt.token,
        identifier: loan.debt.identifier,
        amount: payment - fee - owing,
        recipient: payable(loan.debt.recipient) // currently borrower
      });
    }

    //override to lender
    loan.debt.recipient = payable(lmOwner);
    loan.debt.amount = considerationLength == 3 ? owing : payment - fee;
    consideration[considerationLength == 1 ? 0 : 1] = loan.debt;
  }
}
