// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {LoanManager} from "src/LoanManager.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

contract ChainlinkHook is SettlementHook {
  struct Details {
    address feed;
    uint256 ltvRatio;
  }

  function isActive(
    LoanManager.Loan calldata loan
  ) external override returns (bool) {
    //get the
    ReceivedItem[] memory owing = Pricing(loan.terms.pricing)
      .getPaymentConsideration(loan);
    Details memory details = abi.decode(loan.terms.hookData, (Details));
    int256 nftFloorPrice = _getLatestPrice(details);
    uint256 floor = uint256(nftFloorPrice) * (10 ** (18 - 8));
    //compare whats owing to the ltv trigger for liquidation

    return (floor > owing[0].amount &&
      owing[0].amount / floor > details.ltvRatio);
  }

  /**
   * Returns the latest price
   */
  function _getLatestPrice(
    Details memory details
  ) public view returns (int256) {
    // prettier-ignore

    (
            /*uint80 roundID*/
            ,
            int256 nftFloorPrice,
            /*uint startedAt*/
            ,
            /*uint timeStamp*/
            ,
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(details.feed).latestRoundData();
    return nftFloorPrice;
  }
}
