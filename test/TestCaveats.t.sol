import "./StarPortTest.sol";

contract TestCaveats is StarPortTest {
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
        astariaSettlementHook = new AstariaV1SettlementHook();

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

    function _repayLoan(address borrower, uint256 amount, LoanManager.Loan memory loan) internal {
        vm.startPrank(borrower);
        erc20s[0].approve(address(consideration), amount);
        vm.stopPrank();
        _executeRepayLoan(loan);
    }

    function _createLoan721Collateral20Debt(address lender, uint256 borrowAmount, LoanManager.Terms memory terms) internal returns (LoanManager.Loan memory loan) {
        return _createLoan({
            lender: lender,
            terms: terms,
            collateralItem:
            ConsiderationItem({
                token: address(erc721s[0]),
                startAmount: 1,
                endAmount: 1,
                identifierOrCriteria: 1,
                itemType: ItemType.ERC721,
                recipient: payable(address(custodian))
            }),
            debtItem:
            SpentItem({
                itemType: ItemType.ERC20,
                token: address(erc20s[0]),
                amount: borrowAmount,
                identifier: 0
            })
        });
    }

    function _createLoan20Collateral20Debt(address lender, uint256 borrowAmount, LoanManager.Terms memory terms) internal returns (LoanManager.Loan memory loan) {
        return _createLoan({
            lender: lender,
            terms: terms,
            collateralItem:
            ConsiderationItem({
                token: address(erc20s[1]),
                startAmount: 20,
                endAmount: 20,
                identifierOrCriteria: 0,
                itemType: ItemType.ERC20,
                recipient: payable(address(custodian))
            }),
            debtItem:
            SpentItem({
                itemType: ItemType.ERC20,
                token: address(erc20s[0]),
                amount: borrowAmount,
                identifier: 0
            })
        });
    }

    function _createLoan20Collateral721Debt(address lender, LoanManager.Terms memory terms) internal returns (LoanManager.Loan memory loan) {
        return _createLoan({
            lender: lender,
            terms: terms,
            collateralItem:
            ConsiderationItem({
                token: address(erc20s[0]),
                startAmount: 20,
                endAmount: 20,
                identifierOrCriteria: 0,
                itemType: ItemType.ERC20,
                recipient: payable(address(custodian))
            }),
            debtItem:
            SpentItem({
                itemType: ItemType.ERC721,
                token: address(erc721s[0]),
                amount: 1,
                identifier: 0
            })
        });
    }

    function _createLoan(address lender, LoanManager.Terms memory terms, ConsiderationItem memory collateralItem, SpentItem memory debtItem) internal returns (LoanManager.Loan memory loan) {
        selectedCollateral.push(collateralItem);
        debt.push(debtItem);

        UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
            conduit: address(lenderConduit),
            custodian: address(custodian),
            issuer: lender,
            deadline: block.timestamp + 100,
            terms: terms,
            collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
            debt: debt
        });

        loan = newLoan(
            NewLoanData({
                custodian: address(custodian),
                caveats: new LoanManager.Caveat[](0), // TODO check
                details: abi.encode(loanDetails)
            }),
            Originator(UO),
            selectedCollateral
        );
    }
}
