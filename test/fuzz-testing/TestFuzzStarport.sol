// SPDX-License-Identifier: MIT
import {
    BaseFuzzStarport,
    Starport,
    CaveatEnforcer,
    AdditionalTransfer,
    SpentItem
} from "starport-test/fuzz-testing/BaseFuzzStarport.sol";

import {SimpleInterestPricing} from "starport-test/mocks/pricing/SimpleInterestPricing.sol";
import {FixedTermStatus} from "starport-test/mocks/status/FixedTermStatus.sol";
import {DutchAuctionSettlement} from "starport-test/mocks/settlement/DutchAuctionSettlement.sol";

contract TestFuzzStarport is BaseFuzzStarport {
    function _boundPricingData() internal virtual override returns (bytes memory pricingData) {
        uint256 decimals = _boundMax(_random(), 18);

        SimpleInterestPricing.Details memory details = SimpleInterestPricing.Details({
            rate: _bound(_random(), 1, 10 ** (decimals + 1)), // 1000% interest rate
            carryRate: _boundMax(_random(), 10 ** decimals),
            decimals: decimals
        });
        pricingData = abi.encode(details);
    }

    function _boundStatusData() internal virtual override returns (bytes memory statusData) {
        statusData = abi.encode(FixedTermStatus.Details({loanDuration: _bound(_random(), 1 hours, 1095 days)}));
    }

    function _boundSettlementData() internal virtual override returns (bytes memory settlementData) {
        uint256 startingPrice = _bound(_random(), 0.1 ether, 1000 ether);

        DutchAuctionSettlement.Details memory boundDetails = DutchAuctionSettlement.Details({
            startingPrice: startingPrice,
            endingPrice: _boundMax(_random(), startingPrice - 1),
            window: _bound(_random(), 1, 100 days)
        });

        settlementData = abi.encode(boundDetails);
    }

    function _boundRefinanceData(Starport.Loan memory loan)
        internal
        virtual
        override
        returns (bytes memory newPricing)
    {
        SimpleInterestPricing.Details memory oldDetails =
            abi.decode(loan.terms.pricingData, (SimpleInterestPricing.Details));

        newPricing = abi.encode(
            SimpleInterestPricing.Details({
                rate: _boundMax(_random(), oldDetails.rate - 1),
                carryRate: _boundMax(_random(), 10 ** oldDetails.decimals),
                decimals: oldDetails.decimals
            })
        );
    }
}
