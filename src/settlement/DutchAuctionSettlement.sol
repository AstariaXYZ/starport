pragma solidity ^0.8.17;

import {
    ItemType,
    OfferItem,
    SpentItem,
    ReceivedItem,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {Pricing} from "starport-core/pricing/Pricing.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Starport, Settlement} from "starport-core/settlement/Settlement.sol";

import {BasePricing} from "starport-core/pricing/BasePricing.sol";

abstract contract DutchAuctionSettlement is Settlement, AmountDeriver {
    constructor(Starport SP_) Settlement(SP_) {
        SP = SP_;
    }

    using FixedPointMathLib for uint256;

    error InvalidAmount();

    struct Details {
        uint256 startingPrice;
        uint256 endingPrice;
        uint256 window;
    }

    function postSettlement(Starport.Loan calldata loan, address fulfiller)
        external
        virtual
        override
        returns (bytes4)
    {
        return Settlement.postSettlement.selector;
    }

    function postRepayment(Starport.Loan calldata loan, address fulfiller) external virtual override returns (bytes4) {
        return Settlement.postRepayment.selector;
    }

    function getAuctionStart(Starport.Loan calldata loan) public view virtual returns (uint256);

    function getSettlement(Starport.Loan calldata loan)
        public
        view
        virtual
        override
        returns (ReceivedItem[] memory consideration, address restricted)
    {
        Details memory details = abi.decode(loan.terms.settlementData, (Details));

        uint256 start = getAuctionStart(loan);

        // DutchAuction has failed, allow lender to redeem
        if (start + details.window < block.timestamp) {
            return (new ReceivedItem[](0), loan.issuer);
        }

        uint256 settlementPrice = _locateCurrentAmount({
            startAmount: details.startingPrice,
            endAmount: details.endingPrice,
            startTime: start,
            endTime: start + details.window,
            roundUp: true
        });

        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest =
            BasePricing(loan.terms.pricing).getInterest(loan, pricingDetails.rate, loan.start, block.timestamp, 0);

        uint256 carry = interest.mulWad(pricingDetails.carryRate);

        if (carry > 0 && loan.debt[0].amount + interest - carry < settlementPrice) {
            consideration = new ReceivedItem[](2);
            uint256 excess = settlementPrice - loan.debt[0].amount + interest - carry;
            consideration[0] = ReceivedItem({
                itemType: loan.debt[0].itemType,
                identifier: loan.debt[0].identifier,
                amount: (excess > carry) ? carry : excess,
                token: loan.debt[0].token,
                recipient: payable(loan.originator)
            });
            settlementPrice -= consideration[0].amount;
        } else {
            consideration = new ReceivedItem[](1);
        }

        consideration[consideration.length - 1] = ReceivedItem({
            itemType: loan.debt[0].itemType,
            identifier: loan.debt[0].identifier,
            amount: settlementPrice,
            token: loan.debt[0].token,
            recipient: payable(loan.issuer)
        });
    }

    function validate(Starport.Loan calldata loan) external view virtual override returns (bool) {
        Details memory details = abi.decode(loan.terms.settlementData, (Details));
        return details.startingPrice > details.endingPrice;
    }
}
