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
import {LoanManager, SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";

import {ConduitHelper} from "starport-core/ConduitHelper.sol";
import "forge-std/console2.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";

abstract contract DutchAuctionHandler is SettlementHandler, AmountDeriver, ConduitHelper {
    constructor(LoanManager LM_) SettlementHandler(LM_) {
        LM = LM_;
    }

    using FixedPointMathLib for uint256;

    error InvalidAmount();

    struct Details {
        uint256 startingPrice;
        uint256 endingPrice;
        uint256 window;
    }

    function execute(LoanManager.Loan calldata loan, address fulfiller) external virtual override returns (bytes4) {
        return SettlementHandler.execute.selector;
    }

    function _getAuctionStart(LoanManager.Loan memory loan) internal view virtual returns (uint256);

    function getSettlement(LoanManager.Loan calldata loan)
        public
        view
        virtual
        override
        returns (ReceivedItem[] memory consideration, address restricted)
    {
        Details memory details = abi.decode(loan.terms.handlerData, (Details));

        uint256 start = _getAuctionStart(loan);

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

        if (loan.debt[0].amount + interest <= settlementPrice) {
            consideration = new ReceivedItem[](2);
            consideration[0] = ReceivedItem({
                itemType: loan.debt[0].itemType,
                identifier: loan.debt[0].identifier,
                amount: carry,
                token: loan.debt[0].token,
                recipient: payable(loan.originator)
            });

            settlementPrice -= consideration[0].amount;
        } else if (loan.debt[0].amount + interest - carry <= settlementPrice) {
            consideration = new ReceivedItem[](2);
            consideration[0] = ReceivedItem({
                itemType: loan.debt[0].itemType,
                identifier: loan.debt[0].identifier,
                amount: (settlementPrice - loan.debt[0].amount + interest - carry),
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

    function validate(LoanManager.Loan calldata loan) external view virtual override returns (bool) {
        Details memory details = abi.decode(loan.terms.handlerData, (Details));
        return details.startingPrice > details.endingPrice;
    }
}
