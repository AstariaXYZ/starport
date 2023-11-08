//// SPDX-License-Identifier: MIT
//pragma solidity ^0.8.17;
//
//import {Status} from "starport-core/status/Status.sol";
//import {Pricing} from "starport-core/pricing/Pricing.sol";
//import {Starport} from "starport-core/Starport.sol";
//import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
//import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
//import {Ownable} from "solady/src/auth/Ownable.sol";
//
//contract SignedOracleFeedStatus is Status, Ownable {
//    address public feedSigner;
//
//    struct Details {
//        address feed;
//        uint256 ltvRatio;
//        uint256 delay;
//    }
//
//    struct FeedData {
//        address feed;
//        uint256 floorPrice;
//        uint256 timeStamp;
//    }
//
//    struct Payload {
//        bytes feedData;
//        bytes signature;
//    }
//
//    constructor(address feedSigner_) {
//        feedSigner = feedSigner_;
//        emit FeedSignerUpdated(feedSigner_);
//        _initializeOwner(msg.sender);
//    }
//
//    error InvalidFeedSignature();
//    error InvalidFeedAddress();
//    error FeedDataTooOld();
//
//    event FeedSignerUpdated(address newSigner);
//
//    function setFeedSigner(address newSigner_) external onlyOwner {
//        feedSigner = newSigner_;
//        emit FeedSignerUpdated(newSigner_);
//    }
//
//    function isActive(Starport.Loan calldata loan, bytes calldata extraData) external view override returns (bool) {
//        //get the payment consideration from the
//        (SpentItem[] memory debtOwing, SpentItem[] memory carryPayment) =
//            Pricing(loan.terms.pricing).getPaymentConsideration(loan);
//        Details memory details = abi.decode(loan.terms.statusData, (Details));
//        Payload memory payload = abi.decode(extraData, (Payload));
//        FeedData memory feedData = abi.decode(payload.feedData, (FeedData));
//        if (!SignatureCheckerLib.isValidSignatureNow(feedSigner, keccak256(payload.feedData), payload.signature)) {
//            revert InvalidFeedSignature();
//        }
//        if (details.feed != feedData.feed) {
//            revert InvalidFeedAddress();
//        }
//        if (feedData.timeStamp + details.delay > block.timestamp) {
//            revert FeedDataTooOld();
//        }
//        uint256 floor = feedData.floorPrice;
//        //compare whats owing to the ltv trigger for liquidation
//
//        //TODO: do something if you wanted to do a floor price on more than 1 debt asset
//        return (floor > debtOwing[0].amount && debtOwing[0].amount / floor > details.ltvRatio);
//    }
//}
