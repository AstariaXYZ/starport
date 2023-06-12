// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {LoanManager} from "src/LoanManager.sol";

contract ChainlinkHook is SettlementHook {
  struct Details {
    address feed;
    uint256 ltvRatio;
  }

  function isActive(
    LoanManager.Loan calldata loan
  ) external view override returns (bool) {
    //get the
    uint256 owing = Pricing(loan.pricing).getOwed(loan);
    Details memory details = abi.decode(loan.hookData, (Details));
    int256 nftFloorPrice = _getLatestPrice(details);
    uint256 floor = uint256(nftFloorPrice) * (10 ** (18 - 8));
    //compare whats owing to the ltv trigger for liquidation

    return (floor > owing && owing / floor > details.ltvRatio);
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
