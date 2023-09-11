import "./StarPortTest.sol";

contract TestCaveats is StarPortTest {
    SettlementHook fixedTermHook;
    //    SettlementHook swap;

    SettlementHandler dutchAuctionhandler;
    SettlementHandler englishAuctionhandler;

    Pricing simpleInterestPricing;
    Pricing compoundInterestPricing;


    function setUp() public override {
        super.setUp();

        fixedTermHook = new FixedTermHook();

        dutchAuctionhandler = new DutchAuctionHandler(LM);
        //        englishAuctionhandler = new EnglishAuctionHandler(); // TODO implement

        simpleInterestPricing = new SimpleInterestPricing(LM);
        //        compoundInterestPricing = new CompoundInterestPricing(); // TODO implement
    }

    function testLoanSimpleDutchFixed() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(fixedTermHook),
            handler: address(dutchAuctionhandler),
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
