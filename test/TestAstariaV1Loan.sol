import "./AstariaV1Test.sol";

import {BaseRecall} from "src/hooks/BaseRecall.sol";
// import {Base} from "src/pricing/CompoundInterestPricing.sol";
// import {AstariaV1Pricing} from "src/pricing/AstariaV1Pricing.sol";
import "forge-std/console2.sol";
import {StarPortLib} from "src/lib/StarPortLib.sol";

contract TestAstariaV1Loan is AstariaV1Test {
  using {StarPortLib.getId} for LoanManager.Loan;

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

    debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));
    UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
      conduit: address(lenderConduit),
      custodian: address(custody),
      issuer: lender.addr,
      deadline: block.timestamp + 100,
      terms: terms,
      collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
      debt: debt
    });

    LoanManager.Loan memory loan = newLoan(
      NewLoanData(address(custody), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
      Originator(UO),
      selectedCollateral
    );
    uint256 loanId = loan.getId();
    assertTrue(LM.active(loanId), "LoanId not in active state after a new loan");

    {
      vm.startPrank(recaller.addr);
      vm.expectRevert(BaseRecall.RecallBeforeHoneymoonExpiry.selector);
      // attempt recall before honeymoon period has ended
      BaseRecall(address(hook)).recall(loan, recallerConduit);
      vm.stopPrank();
    }
    {
      // refinance with before recall is initiated
      vm.startPrank(refinancer.addr);
      vm.expectRevert(Pricing.InvalidRefinance.selector);
      LM.refinance(
        loan,
        abi.encode(BasePricing.Details({rate: (uint256(1e16) * 100) / (365 * 1 days), carryRate: 0})),
        refinancerConduit
      );
      vm.stopPrank();
    }
    uint256 stake;
    {
      uint256 balanceBefore = erc20s[0].balanceOf(recaller.addr);
      uint256 recallContractBalanceBefore = erc20s[0].balanceOf(address(hook));
      BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
      vm.warp(block.timestamp + details.honeymoon);
      vm.startPrank(recaller.addr);

      BaseRecall recallContract = BaseRecall(address(hook));
      recallContract.recall(loan, recallerConduit);
      vm.stopPrank();

      uint256 balanceAfter = erc20s[0].balanceOf(recaller.addr);
      uint256 recallContractBalanceAfter = erc20s[0].balanceOf(address(hook));

      BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
      stake = BasePricing(address(pricing)).calculateInterest(
        details.recallStakeDuration, loan.debt[0].amount, pricingDetails.rate
      );
      assertEq(balanceBefore, balanceAfter + stake, "Recaller balance not transfered correctly");
      assertEq(
        recallContractBalanceBefore + stake,
        recallContractBalanceAfter,
        "Balance not transfered to recall contract correctly"
      );
    }
    {
      BaseRecall recallContract = BaseRecall(address(hook));
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
      vm.expectRevert(AstariaV1Pricing.InsufficientRefinance.selector);
      vm.startPrank(refinancer.addr);
      LM.refinance(
        loan,
        abi.encode(BasePricing.Details({rate: (uint256(1e16) * 100) / (365 * 1 days), carryRate: 0})),
        refinancerConduit
      );
      vm.stopPrank();
    }
    {
      // refinance with correct terms
      uint256 newLenderBefore = erc20s[0].balanceOf(refinancer.addr);
      uint256 oldLenderBefore = erc20s[0].balanceOf(lender.addr);
      uint256 recallerBefore = erc20s[0].balanceOf(recaller.addr);
      BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
      vm.startPrank(refinancer.addr);
      vm.warp(block.timestamp + (details.recallWindow / 2));
      LM.refinance(
        loan, abi.encode(BasePricing.Details({rate: details.recallMax / 2, carryRate: 0})), refinancerConduit
      );
      vm.stopPrank();
      uint256 delta_t = block.timestamp - loan.start;
      BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
      uint256 interest =
        BasePricing(address(pricing)).calculateInterest(delta_t, loan.debt[0].amount, pricingDetails.rate);
      uint256 newLenderAfter = erc20s[0].balanceOf(refinancer.addr);
      uint256 oldLenderAfter = erc20s[0].balanceOf(lender.addr);
      assertEq(
        oldLenderAfter, oldLenderBefore + loan.debt[0].amount + interest, "Payment to old lender calculated incorrectly"
      );
      assertEq(
        newLenderAfter,
        newLenderBefore - (loan.debt[0].amount + interest + stake),
        "Payment from new lender calculated incorrectly"
      );
      assertEq(recallerBefore + stake, erc20s[0].balanceOf(recaller.addr), "Recaller did not recover stake as expected");
      assertTrue(LM.inactive(loanId), "LoanId not properly flipped to inactive after refinance");
    }
    {
      uint256 withdrawerBalanceBefore = erc20s[0].balanceOf(address(this));
      uint256 recallContractBalanceBefore = erc20s[0].balanceOf(address(hook));
      BaseRecall recallContract = BaseRecall(address(hook));

      // attempt a withdraw after the loan has been successfully refinanced
      recallContract.withdraw(loan, payable(address(this)));
      uint256 withdrawerBalanceAfter = erc20s[0].balanceOf(address(this));
      uint256 recallContractBalanceAfter = erc20s[0].balanceOf(address(hook));
      assertEq(withdrawerBalanceBefore + stake, withdrawerBalanceAfter, "Withdrawer did not recover stake as expected");
      assertEq(
        recallContractBalanceBefore - stake,
        recallContractBalanceAfter,
        "BaseRecall did not return the stake as expected"
      );
    }
  }
}
