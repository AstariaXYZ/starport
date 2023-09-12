import "./AstariaV1Test.sol";

import {BaseRecall} from "src/hooks/BaseRecall.sol";
import "forge-std/console2.sol";
contract TestAstariaV1Loan is AstariaV1Test {

  // 
  function testNewLoanERC721CollateralDefaultTermsRecallRevertBeforeHoneymoon() public {
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

    uint256 loanId = LM.getLoanIdFromLoan(loan);
    console2.log("meow", LM.issued(loanId));

    vm.startPrank(recaller.addr);
    vm.expectRevert(BaseRecall.RecallBeforeHoneymoonExpiry.selector);
    BaseRecall(address(hook)).recall(loan, recallerConduit);
    vm.stopPrank();
    
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

    function testNewLoanERC721CollateralDefaultTermsRecallAfterHoneymoon() public {
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

    BaseRecall.Details memory details =  abi.decode(loan.terms.hookData, (BaseRecall.Details));
    vm.warp(block.timestamp + details.honeymoon);
    vm.startPrank(recaller.addr);
    BaseRecall(address(hook)).recall(loan, recallerConduit);
    vm.stopPrank();
    
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