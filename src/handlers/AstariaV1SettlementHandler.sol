pragma solidity =0.8.17;

import {
  LoanManager,
  SpentItem,
  ReceivedItem,
  SettlementHandler
} from "src/handlers/SettlementHandler.sol";

contract AstariaV1SettlementHandler is SettlementHandler {
  constructor(LoanManager LM_) SettlementHandler(LM_) {}

  function getSettlement(
    LoanManager.Loan memory loan
  )
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory, address restricted)
  {
    return (
      new ReceivedItem[](0),
      LM.getIssuer(loan)
    );
  }

  function validate(
    LoanManager.Loan calldata loan
  ) external view override returns (bool) {
    return true;
  }
}
