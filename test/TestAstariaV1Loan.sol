import "./StarPortTest.sol";

contract TestAstariaV1Loan is StarPortTest {
  function testNewLoanERC721CollateralDefaultTerms()
    public
    returns (LoanManager.Loan memory)
  {
    Custodian custody = Custodian(LM.defaultCustodian());

    LoanManager.Terms memory terms = LoanManager.Terms({
      hook: address(hook),
      handler: address(handler),
      pricing: address(pricing),
      pricingData: defaultPricingData,
      handlerData: defaultHandlerData,
      hookData: defaultHookData
    });

    selectedCollateral.push(
      ConsiderationItem({
        token: address(erc721s[0]),
        startAmount: 1,
        endAmount: 1,
        identifierOrCriteria: 1,
        itemType: ItemType.ERC721,
        recipient: payable(address(custody))
      })
    );

    debt.push(
      SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: 100,
        identifier: 0
      })
    );
    UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
      conduit: address(lenderConduit),
      custodian: address(custody),
      issuer: lender.addr,
      deadline: block.timestamp + 100,
      terms: terms,
      collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
      debt: debt
    });
    bool isTrusted = true;

    TermEnforcer TE = new TermEnforcer();

    TermEnforcer.Details memory TEDetails = TermEnforcer.Details({
      pricing: address(pricing),
      hook: address(hook),
      handler: address(handler)
    });

    LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
    caveats[0] = LoanManager.Caveat({
      enforcer: address(TE),
      terms: abi.encode(TEDetails)
    });

    return
      newLoan(
        NewLoanData(address(custody), caveats, abi.encode(loanDetails)),
        Originator(UO),
        selectedCollateral
      );
  }

  function testNewLoanERC721CollateralDefaultTermsRefinance() public {
    Custodian custody = Custodian(LM.defaultCustodian());

    LoanManager.Terms memory terms = LoanManager.Terms({
      hook: address(hook),
      handler: address(handler),
      pricing: address(pricing),
      pricingData: defaultPricingData,
      handlerData: defaultHandlerData,
      hookData: defaultHookData
    });

    selectedCollateral.push(
      ConsiderationItem({
        token: address(erc721s[0]),
        startAmount: 1,
        endAmount: 1,
        identifierOrCriteria: 1,
        itemType: ItemType.ERC721,
        recipient: payable(address(custody))
      })
    );

    debt.push(
      SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: 100,
        identifier: 0
      })
    );
    UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
      conduit: address(lenderConduit),
      custodian: address(custody),
      issuer: lender.addr,
      deadline: block.timestamp + 100,
      terms: terms,
      collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
      debt: debt
    });
    bool isTrusted = true;

    LoanManager.Loan memory loan = newLoan(
      NewLoanData(
        address(custody),
        new LoanManager.Caveat[](0),
        abi.encode(loanDetails)
      ),
      Originator(UO),
      selectedCollateral
    );
    vm.startPrank(refinancer.addr);
    LM.refinance(
      loan,
      abi.encode(
        BasePricing.Details({
          rate: (uint256(1e16) * 100) / (365 * 1 days),
          carryRate: 0
        })
      ),
      refinancerConduit
    );
    vm.stopPrank();
  }

}