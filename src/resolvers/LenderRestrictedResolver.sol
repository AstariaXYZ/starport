pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import "src/validators/Validator.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Resolver} from "src/resolvers/Resolver.sol";

contract LenderRestrictedResolver is Resolver {
  function getUnlockConsideration(
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
