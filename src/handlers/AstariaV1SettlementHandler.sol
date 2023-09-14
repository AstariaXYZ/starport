pragma solidity =0.8.17;

import {
  LoanManager,
  SpentItem,
  ReceivedItem,
  SettlementHandler
} from "src/handlers/SettlementHandler.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {DutchAuctionHandler} from "src/handlers/DutchAuctionHandler.sol";

contract AstariaV1SettlementHandler is DutchAuctionHandler {
  constructor(LoanManager LM_) DutchAuctionHandler(LM_) {}

  function getSettlement(
    LoanManager.Loan memory loan
  )
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory, address restricted)
  {
    // v1 handler is dynamic in that if a recall is active we check the hook
    // check the recall status is it going to the lender? if so, send to lender
    // otherwise compute the dutch price
    //get base recall status from the hook
    if (SettlementHook(loan.terms.hook).isRecalled(loan)) {
      revert();
    }
    if (SettlementHook(loan.terms.hook).wasActive(loan)) {
      return super.getSettlement(loan);
    } else {
      return (new ReceivedItem[](0), LM.getIssuer(loan));
    }
  }

  function validate(
    LoanManager.Loan calldata loan
  ) external view override returns (bool) {
    return true;
  }
}
