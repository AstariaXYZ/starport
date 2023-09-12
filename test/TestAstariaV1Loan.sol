import "./AstariaV1Test.sol";

import {BaseRecall} from "src/hooks/BaseRecall.sol";
// import {AstariaV1Pricing} from "src/pricing/AstariaV1Pricing.sol";
import "forge-std/console2.sol";
contract TestAstariaV1Loan is AstariaV1Test {

  function testNewLoanERC721CollateralDefaultTermsRecall() public {
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

    {
      vm.startPrank(recaller.addr);
      vm.expectRevert(BaseRecall.RecallBeforeHoneymoonExpiry.selector);
      // attempt recall before honeymoon period has ended
      BaseRecall(address(hook)).recall(loan, recallerConduit);
      vm.stopPrank();
    }
    {
      uint256 balanceBefore = erc20s[0].balanceOf(recaller.addr);
      uint256 recallContractBalanceBefore = erc20s[0].balanceOf(address(hook)); 
      BaseRecall.Details memory details =  abi.decode(loan.terms.hookData, (BaseRecall.Details));
      vm.warp(block.timestamp + details.honeymoon);
      vm.startPrank(recaller.addr);

      BaseRecall recallContract = BaseRecall(address(hook));
      recallContract.recall(loan, recallerConduit);
      vm.stopPrank();
      
      uint256 balanceAfter = erc20s[0].balanceOf(recaller.addr);
      uint256 recallContractBalanceAfter = erc20s[0].balanceOf(address(hook)); 

      BasePricing.Details memory pricingDetails =  abi.decode(loan.terms.pricingData, (BasePricing.Details));
      uint256 interest = BasePricing(address(pricing)).calculateInterest(details.recallStakeDuration, loan.debt[0].amount, pricingDetails.rate);
      assertEq(balanceBefore, balanceAfter + interest, "Recaller balance not transfered correctly");
      assertEq(recallContractBalanceBefore + interest, recallContractBalanceAfter, "Balance not transfered to recall contract correctly");
    }
    {
      BaseRecall recallContract = BaseRecall(address(hook));
      uint256 loanId = LM.getLoanIdFromLoan(loan);
      address recallerAddr;
      uint64 start;
      (recallerAddr, start) = recallContract.recalls(loanId);

      assertEq(recaller.addr, recallerAddr, "Recaller address logged incorrectly");
      assertEq(start, block.timestamp, "Recall start logged incorrectly");
    }
    {
      BaseRecall recallContract = BaseRecall(address(hook));
      vm.expectRevert(BaseRecall.LoanHasNotBeenRefinanced.selector);
      // attempt a withdraw without the loan being refinanced
      recallContract.withdraw(loan, payable(address(this)));
    }
    {
      // refinance with incorrect terms
      // LM.refinance()
    }

    {
      // refinance with correct terms
      // check balances
      // old lender balance
      // new lender balance
      // validate terms
      // validate loanId is deleted
      // valdiate extraData is deleted
      
    }
    {
      // attempt withdraw
      // validate balances
    }
    // vm.startPrank(refinancer.addr);
    // LM.refinance(
    //   loan,
    //   abi.encode(
    //     BasePricing.Details({
    //       rate: (uint256(1e16) * 100) / (365 * 1 days),
    //       carryRate: 0
    //     })
    //   ),
    //   refinancerConduit
    // );
    // vm.stopPrank();
  }
}