import "./StarPortTest.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import { LibString } from "solady/src/utils/LibString.sol";

import "forge-std/console.sol";

contract TestLoanCombinations is StarPortTest {
    SettlementHook fixedTermHook;
    SettlementHook astariaSettlementHook;
    //    SettlementHook swap;

    SettlementHandler dutchAuctionHandler;
    SettlementHandler englishAuctionHandler;
    SettlementHandler astariaSettlementHandler;

    Pricing simpleInterestPricing;
    Pricing astariaPricing;

    ConsiderationInterface public constant seaport = ConsiderationInterface(0x2e234DAe75C793f67A35089C9d99245E1C58470b);


    function setUp() public override {
        super.setUp();

        fixedTermHook = new FixedTermHook();
        astariaSettlementHook = new AstariaV1SettlementHook(LM);

        dutchAuctionHandler = new DutchAuctionHandler(LM);
        englishAuctionHandler = new EnglishAuctionHandler({
            LM_: LM,
            consideration_: seaport,
            EAZone_: 0x110b2B128A9eD1be5Ef3232D8e4E41640dF5c2Cd
        });
        astariaSettlementHandler = new AstariaV1SettlementHandler(LM);

        simpleInterestPricing = new SimpleInterestPricing(LM);
        astariaPricing = new AstariaV1Pricing(LM);
    }

    // TODO test liquidations
    function testLoan721for20SimpleInterestDutchFixedRepay() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(fixedTermHook),
            handler: address(dutchAuctionHandler),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan = _createLoan721Collateral20Debt({
            lender: lender.addr,
            borrowAmount: 100,
            terms: terms
        });
        skip(10 days);

        _repayLoan({
            borrower: borrower.addr,
            amount: 375,
            loan: loan
        });
    }

    function testLoan20for20SimpleInterestDutchFixedRepay() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(fixedTermHook),
            handler: address(dutchAuctionHandler),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan = _createLoan20Collateral20Debt({
            lender: lender.addr,
            borrowAmount: 100,
            terms: terms
        });
        skip(10 days);

        _repayLoan({
            borrower: borrower.addr,
            amount: 375,
            loan: loan
        });
    }

    function testLoan20For721SimpleInterestDutchFixedRepay() public {
//        LoanManager.Terms memory terms = LoanManager.Terms({
//            hook: address(fixedTermHook),
//            handler: address(dutchAuctionHandler),
//            pricing: address(simpleInterestPricing),
//            pricingData: defaultPricingData,
//            handlerData: defaultHandlerData,
//            hookData: defaultHookData
//        });
//        LoanManager.Loan memory loan = _createLoan20Collateral721Debt({
//            lender: lender.addr,
//            terms: terms
//        });
//        skip(10 days);

//        _repayLoan({ // TODO different repay
//            borrower: borrower.addr,
//            amount: 375,
//            loan: loan
//        });
    }

    function testLoanAstariaSettlementRepay() public {
        bytes memory astariaPricingData = new bytes(0);
        bytes memory astariaSettlementHandlerData = new bytes(0);
        bytes memory astariaSettlementHookData = new bytes(0);

        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(astariaSettlementHook),
            handler: address(astariaSettlementHandler),
            pricing: address(astariaPricing),
            pricingData: astariaPricingData,
            handlerData: astariaSettlementHandlerData,
            hookData: astariaSettlementHookData
        });
        LoanManager.Loan memory loan = _createLoan721Collateral20Debt({
            lender: lender.addr,
            borrowAmount: 100,
            terms: terms
        });
//        skip(10 days);
//
//        _repayLoan({
//            borrower: borrower.addr,
//            amount: 375,
//            loan: loan
//        });
    }

    function testLoanSimpleInterestEnglishFixed() public {
        uint256[] memory reservePrice = new uint256[](1);
        reservePrice[0] = 300;
        bytes memory englishAuctionHandlerData = abi.encode(
            EnglishAuctionHandler.Details({
                reservePrice: reservePrice,
                window: 7 days
            })
        );

        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(fixedTermHook),
            handler: address(englishAuctionHandler),
            pricing: address(simpleInterestPricing),
            pricingData: defaultPricingData,
            handlerData: englishAuctionHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan = _createLoan721Collateral20Debt({
            lender: lender.addr,
            borrowAmount: 100,
            terms: terms
        });
        skip(10 days);

        _repayLoan({
            borrower: borrower.addr,
            amount: 375,
            loan: loan
        });
    }
}
