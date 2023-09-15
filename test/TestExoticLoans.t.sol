import "./StarPortTest.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";

import "forge-std/console.sol";

contract TestExoticLoans is StarPortTest {
    function testSwap() public {
        SwapHook swapHook = new SwapHook();
        SwapHandler swapHandler = new SwapHandler(LM);
        SwapPricing swapPricing = new SwapPricing(LM);

        bytes memory swapPricingData = "";
        bytes memory swapHandlerData = "";
        bytes memory swapHookData = "";

        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(swapHook),
            handler: address(swapHandler),
            pricing: address(swapPricing),
            pricingData: swapPricingData,
            handlerData: swapHandlerData,
            hookData: swapHookData
        });

//        uint256 initialErc201balance = erc20s[1].balanceOf(borrower.addr);
//        uint256 initialErc202balance = erc20s[0].balanceOf(borrower.addr);

        LoanManager.Loan memory loan = _createLoan20Collateral20Debt({
            lender: lender.addr,
            collateralAmount: 20, // erc20s[1]
            borrowAmount: 100, // erc20s[0]
            terms: terms
        });

//        assertEq(erc20s[1].balanceOf(borrower.addr), initialErc201balance);
//        assertEq(erc20s[0].balanceOf(borrower.addr), initialErc202balance);
//        skip(10 days);
//
//        _repayLoan({
//            borrower: borrower.addr,
//            amount: 375,
//            loan: loan
//        });
    }
}

contract SwapHook is SettlementHook {
    function isActive(LoanManager.Loan calldata loan) external view override returns (bool) {
        return true;
    }
}

contract SwapHandler is SettlementHandler {

    constructor(LoanManager LM_) SettlementHandler(LM_) {}

    function execute(
        LoanManager.Loan calldata loan
    ) external override returns (bytes4) {
        return bytes4(0);
    }

    function validate(
        LoanManager.Loan calldata loan
    ) external view override returns (bool) {
        return true;
    }

    function getSettlement(
        LoanManager.Loan memory loan
    ) external override returns (ReceivedItem[] memory consideration, address restricted) {
        return (new ReceivedItem[](0), address(0));
    }
}

contract SwapPricing is Pricing {

    constructor(LoanManager LM_) Pricing(LM_) {}

    function getPaymentConsideration(
        LoanManager.Loan memory loan
    ) public view override returns (ReceivedItem[] memory, ReceivedItem[] memory) {
        return (new ReceivedItem[](0), new ReceivedItem[](0));
    }

    function isValidRefinance(
        LoanManager.Loan memory loan,
        bytes memory newPricingData,
        address caller
    ) external view override returns (ReceivedItem[] memory, ReceivedItem[] memory, ReceivedItem[] memory) {
        return (new ReceivedItem[](0), new ReceivedItem[](0), new ReceivedItem[](0));
    }
}
