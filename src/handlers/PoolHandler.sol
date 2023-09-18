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
import {StarPortLib} from "src/lib/StarPortLib.sol";

contract AstariaV1SettlementHandler is DutchAuctionHandler {
  using {StarPortLib.getId} for LoanManager.Loan;

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
    return (new ReceivedItem[](0), address(0));
  }

  function validate(
    LoanManager.Loan calldata loan
  ) external view virtual override returns (bool) {
    return true;
  }
}
