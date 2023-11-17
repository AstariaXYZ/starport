pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {Validation} from "starport-core/lib/Validation.sol";
import "forge-std/console.sol";
import "../utils/DeepEq.sol";
import {DutchAuctionSettlement} from "starport-core/settlement/DutchAuctionSettlement.sol";
import {FixedTermStatus} from "starport-core/status/FixedTermStatus.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";

contract MockBasePricing is BasePricing {
    constructor(Starport SP_) Pricing(SP_) {}

    function calculateInterest(uint256 delta_t, uint256 amount, uint256 rate, uint256 decimals)
        public
        pure
        override
        returns (uint256)
    {
        return amount;
    }

    function getRefinanceConsideration(Starport.Loan calldata loan, bytes memory newPricingData, address fulfiller)
        external
        view
        virtual
        override
        returns (
            SpentItem[] memory repayConsideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalTransfers
        )
    {
        return (new SpentItem[](0), new SpentItem[](0), new AdditionalTransfer[](0));
    }
}

contract ModuleTesting is StarportTest, DeepEq {
    using FixedPointMathLib for uint256;
    using LibString for string;

    function testModuleValidation() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});

        Starport.Loan memory badLoan = loanCopy(loan);
        badLoan.terms.statusData = abi.encode(FixedTermStatus.Details({loanDuration: 0}));
        badLoan.terms.settlementData =
            abi.encode(DutchAuctionSettlement.Details({startingPrice: 0, endingPrice: 0, window: 0}));
        badLoan.terms.pricingData = abi.encode(BasePricing.Details({rate: 0, carryRate: 0, decimals: 0}));
        assertEq(
            Validation(loan.terms.status).validate(loan), Validation.validate.selector, "Loan has invalid status data"
        );
        assertEq(Validation(loan.terms.status).validate(badLoan), bytes4(0xFFFFFFFF), "Loan has valid status data");
        assertEq(
            Validation(loan.terms.pricing).validate(loan), Validation.validate.selector, "Loan has invalid pricing data"
        );
        assertEq(Validation(loan.terms.pricing).validate(badLoan), bytes4(0xFFFFFFFF), "Loan has valid pricing data");
        assertEq(
            Validation(loan.terms.settlement).validate(loan),
            Validation.validate.selector,
            "Loan has invalid settlement data"
        );
        assertEq(
            Validation(loan.terms.settlement).validate(badLoan), bytes4(0xFFFFFFFF), "Loan has valid settlement data"
        );

        MockBasePricing dummy = new MockBasePricing(SP);
        assertEq(Validation(dummy).validate(loan), Validation.validate.selector, "Loan has invalid pricing data");
        assertEq(Validation(dummy).validate(badLoan), bytes4(0xFFFFFFFF), "Loan has valid pricing data");
    }

    function testFixedTermDutchAuctionSettlement() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});
        FixedTermStatus.Details memory details = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));

        uint256 expectedAuctionStart = block.timestamp + details.loanDuration;

        assertEq(
            expectedAuctionStart,
            FixedTermDutchAuctionSettlement(loan.terms.settlement).getAuctionStart(loan),
            "Auction start time is not correct"
        );
    }

    function testFixedTermDutchAuctionSettlementNotValid() public {
        DutchAuctionSettlement.Details memory details =
            DutchAuctionSettlement.Details({startingPrice: 1 ether, endingPrice: 10 ether, window: 7 days});
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: abi.encode(details),
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});

        assertEq(
            FixedTermDutchAuctionSettlement(loan.terms.settlement).validate(loan), bytes4(0xFFFFFFFF), "Loan is valid"
        );
    }

    function testFixedTermDutchAuctionSettlementValid() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});

        assertEq(
            FixedTermDutchAuctionSettlement(loan.terms.settlement).validate(loan),
            Validation.validate.selector,
            "Loan is invalid"
        );
    }

    function testFixedTermDutchAuctionSettlementGetSettlementAuctionExpired() public {
        Starport.Terms memory terms = Starport.Terms({
            status: address(fixedTermStatus),
            settlement: address(dutchAuctionSettlement), //fixed term dutch auction
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        Starport.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});
        FixedTermStatus.Details memory details = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));

        DutchAuctionSettlement.Details memory dutchAuctionDetails =
            abi.decode(loan.terms.settlementData, (DutchAuctionSettlement.Details));
        skip(details.loanDuration + dutchAuctionDetails.window + 1);
        (ReceivedItem[] memory settlementConsideration, address authorized) =
            FixedTermDutchAuctionSettlement(loan.terms.settlement).getSettlementConsideration(loan);
        _deepEq(settlementConsideration, new ReceivedItem[](0));
        assertEq(authorized, loan.issuer, "Authorized is not correct");
    }
}
