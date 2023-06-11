// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Trigger} from "src/triggers/Trigger.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {LoanManager} from "src/LoanManager.sol";

contract ChainlinkTrigger is Trigger {
  struct Details {
    address feed;
    uint256 ltvRatio;
  }

  function isLoanHealthy(
    LoanManager.Loan calldata loan
  ) external view override returns (bool) {
    //get the
    uint256 owing = Pricing(loan.pricing).getOwed(loan);
    Details memory details = abi.decode(loan.triggerData, (Details));
    int nftFloorPrice = _getLatestPrice(details);
    uint256 floor = uint256(nftFloorPrice) * (10 ** (18 - 8));
    //compare whats owing to the ltv trigger for liquidation

    return (floor > owing && owing / floor > details.ltvRatio);
  }

  /**
   * Returns the latest price
   */
  function _getLatestPrice(Details memory details) public view returns (int) {
    // prettier-ignore

    (
        /*uint80 roundID*/,
        int nftFloorPrice,
        /*uint startedAt*/,
        /*uint timeStamp*/,
        /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(details.feed).latestRoundData();
    return nftFloorPrice;
  }
}
