pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import {
  SpentItem,
  ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract Resolver {
  function resolve(
    LoanManager.Loan calldata loan
  ) external virtual returns (bytes4) {
    return Resolver.resolve.selector;
  }

  function getUnlockConsideration(
    LoanManager.Loan memory loan,
    SpentItem[] calldata maximumSpent,
    uint256 owing,
    address payable lmOwner
  )
    external
    view
    virtual
    returns (ReceivedItem[] memory consideration, address restricted);
}
