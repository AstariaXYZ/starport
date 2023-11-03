pragma solidity ^0.8.17;

import {Starport, SpentItem, ReceivedItem, Settlement} from "starport-core/settlement/Settlement.sol";
import {BaseStatus} from "starport-core/status/BaseStatus.sol";
import {BaseRecall} from "starport-core/status/BaseRecall.sol";
import {DutchAuctionSettlement} from "starport-core/settlement/DutchAuctionSettlement.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

import {Pricing} from "starport-core/pricing/Pricing.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import "forge-std/console2.sol";

contract AstariaV1Settlement is DutchAuctionSettlement {
    using {StarportLib.getId} for Starport.Loan;
    using FixedPointMathLib for uint256;

    constructor(Starport SP_) DutchAuctionSettlement(SP_) {}

    error NoAuction();
    error LoanNotRecalled();
    error ExecuteHandlerNotImplemented();
    error InvalidHandler();

    function getCurrentAuctionPrice(Starport.Loan calldata loan) public view virtual returns (uint256) {
        (address recaller, uint64 recallStart) = BaseRecall(loan.terms.status).recalls(loan.getId());
        if (recaller == loan.issuer || recallStart == uint256(0) || recaller == address(0)) {
            revert NoAuction();
        }

        uint256 start = _getAuctionStart(loan, recallStart);

        Details memory details = abi.decode(loan.terms.settlementData, (Details));

        return _locateCurrentAmount({
            startAmount: details.startingPrice,
            endAmount: details.endingPrice,
            startTime: start,
            endTime: start + details.window,
            roundUp: true
        });
    }

    function getAuctionStart(Starport.Loan calldata loan) public view virtual override returns (uint256) {
        (, uint64 start) = BaseRecall(loan.terms.status).recalls(loan.getId());
        if (start == 0) {
            revert LoanNotRecalled();
        }
        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));
        return start + details.recallWindow + 1;
    }

    function _getAuctionStart(Starport.Loan calldata loan, uint64 start) internal view virtual returns (uint256) {
        BaseRecall.Details memory details = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        return start + details.recallWindow + 1;
    }

    function getSettlement(Starport.Loan calldata loan)
        public
        view
        virtual
        override
        returns (ReceivedItem[] memory consideration, address restricted)
    {
        (address recaller, uint64 recallStart) = BaseRecall(loan.terms.status).recalls(loan.getId());

        if (recaller == address(0) || recallStart == uint256(0)) {
            revert LoanNotRecalled();
        }
        if (recaller == loan.issuer) {
            return (new ReceivedItem[](0), recaller);
        }

        uint256 start = _getAuctionStart(loan, recallStart);
        Details memory details = abi.decode(loan.terms.settlementData, (Details));

        // DutchAuction has failed, give the NFT back to the lender (if they want it 😐)
        if (start + details.window < block.timestamp) {
            return (new ReceivedItem[](0), loan.issuer);
        }

        // DutchAuction price for anyone to bid on
        uint256 settlementPrice = _locateCurrentAmount({
            startAmount: details.startingPrice,
            endAmount: details.endingPrice,
            startTime: start,
            endTime: start + details.window,
            roundUp: true
        });

        consideration = new ReceivedItem[](3);
        uint256 i = 0;
        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest =
            BasePricing(loan.terms.pricing).getInterest(loan, pricingDetails.rate, loan.start, block.timestamp, 0);

        uint256 carry = interest.mulWad(pricingDetails.carryRate);

        if (carry > 0 && loan.debt[0].amount + interest - carry < settlementPrice) {
            uint256 excess = settlementPrice - loan.debt[0].amount + interest - carry;
            consideration[i] = ReceivedItem({
                itemType: loan.debt[0].itemType,
                identifier: loan.debt[0].identifier,
                amount: (excess > carry) ? carry : excess,
                token: loan.debt[0].token,
                recipient: payable(loan.originator)
            });
            settlementPrice -= consideration[i].amount;
            unchecked {
                ++i;
            }
        }

        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.statusData, (BaseRecall.Details));

        uint256 recallerReward = (settlementPrice).mulWad(hookDetails.recallerRewardRatio);
        if (recallerReward > 0) {
            consideration[i] = ReceivedItem({
                itemType: loan.debt[0].itemType,
                identifier: loan.debt[0].identifier,
                amount: settlementPrice.mulWad(hookDetails.recallerRewardRatio),
                token: loan.debt[0].token,
                recipient: payable(recaller)
            });
            settlementPrice -= consideration[i].amount;
            unchecked {
                ++i;
            }
        }

        consideration[i] = ReceivedItem({
            itemType: loan.debt[0].itemType,
            identifier: loan.debt[0].identifier,
            amount: settlementPrice,
            token: loan.debt[0].token,
            recipient: payable(loan.issuer)
        });

        unchecked {
            ++i;
        }

        assembly {
            mstore(consideration, i)
        }
    }

    function execute(Starport.Loan calldata loan, address fulfiller) external virtual override returns (bytes4) {
        revert ExecuteHandlerNotImplemented();
    }

    function validate(Starport.Loan calldata loan) external view virtual override returns (bool) {
        if (loan.terms.settlement != address(this)) {
            revert InvalidHandler();
        }
        Details memory details = abi.decode(loan.terms.settlementData, (Details)); //will revert if this fails
        return (details.startingPrice > details.endingPrice);
    }
}
