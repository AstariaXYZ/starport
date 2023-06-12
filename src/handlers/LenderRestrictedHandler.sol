pragma solidity =0.8.17;

import {
  LoanManager,
  SpentItem,
  ReceivedItem,
  SettlementHandler
} from "src/handlers/SettlementHandler.sol";

contract LenderRestrictedHandler is SettlementHandler {
  function getSettlement(
    LoanManager.Loan memory loan,
    SpentItem[] calldata maximumSpent,
    uint256 owing,
    address payable lmOwner
  )
    external
    view
    virtual
    override
    returns (ReceivedItem[] memory, address restricted)
  {
    return (new ReceivedItem[](0), lmOwner);
  }
}
