import "./StarPortTest.sol";

contract TestRepayLoan is StarPortTest {
  function testRepayLoan() public {
    uint256 borrowAmount = 100;
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
        recipient: payable(address(custodian))
      })
    );

    debt.push(
      SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: borrowAmount,
        identifier: 0 // 0 for ERC20
      })
    );

    UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
      conduit: address(lenderConduit),
      custodian: address(custodian),
      issuer: lender.addr,
      deadline: block.timestamp + 100,
      terms: terms,
      collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
      debt: debt
    });
    bool isTrusted = false;

    LoanManager.Loan memory activeLoan = newLoan(
      NewLoanData(
        address(custodian),
        new LoanManager.Caveat[](0),
        abi.encode(loanDetails)
      ),
      Originator(UO),
      selectedCollateral
    );
    vm.startPrank(borrower.addr);
    skip(10 days);
    erc20s[0].approve(address(consideration), 375);
    vm.stopPrank();
    _executeRepayLoan(activeLoan);
  }
}
