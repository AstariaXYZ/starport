pragma solidity =0.8.17;

import {
  LoanManager,
  SpentItem,
  ReceivedItem,
  SettlementHandler
} from "src/handlers/SettlementHandler.sol";
import {BaseHook} from "src/hooks/BaseHook.sol";
import {BaseRecall} from "src/hooks/BaseRecall.sol";
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
    (address recaller, ) = BaseRecall(loan.terms.hook).recalls(
      LM.getLoanIdFromLoan(loan)
    );

    if (recaller == loan.issuer) {
      return (new ReceivedItem[](0), recaller);
    } else {
      return DutchAuctionHandler(address(this)).getSettlement(loan);
    }
  }

  function validate(
    LoanManager.Loan calldata loan
  ) external view virtual override returns (bool) {
    return true;
  }
}
