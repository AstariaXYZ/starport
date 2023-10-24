import "starport-test/WhackyTest.sol";

import {BaseRecall} from "starport-core/hooks/BaseRecall.sol";
import "forge-std/console2.sol";
import {StarPortLib, Actions} from "starport-core/lib/StarPortLib.sol";
import {Enforcer} from "starport-core/Enforcer.sol";
import {BaseEnforcer} from "starport-core/BaseEnforcer.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";

contract NovelOriginationTest is WhackyTest {
    using {StarPortLib.getId} for LoanManager.Loan;

    function testNovelOriginationForGas() public {
      
      vm.startPrank(borrower.addr);
      erc721s[0].setApprovalForAll(address(origination), true);
      vm.stopPrank();

      vm.startPrank(lender.addr);
      erc20s[0].approve(address(origination), 1);
      vm.stopPrank();
      
      SpentItem[] memory collateral = new SpentItem[](1);
      collateral[0] = SpentItem({
          itemType: ItemType.ERC721,
          token: address(erc721s[0]),
          identifier: 1,
          amount: 1
      });

      SpentItem[] memory debt = new SpentItem[](1);
      debt[0] = SpentItem({
          itemType: ItemType.ERC20,
          token: address(erc20s[0]),
          identifier: 0,
          amount: 1
      });

      LoanManager.Loan memory loan = LoanManager.Loan({
        start: 0,
        custodian: address(custodian),
        borrower: borrower.addr,
        issuer: address(0),
        originator: address(0),
        collateral: collateral,
        debt: debt,
        terms: LoanManager.Terms({
            hook: address(0),
            handler: address(0),
            pricing: address(0),
            pricingData: new bytes(0),
            handlerData: new bytes(0),
            hookData: new bytes(0)
        })
      });

      BaseEnforcer.Details memory caveat = BaseEnforcer.Details({
        loan: loan
      });

      Enforcer.Caveat memory borrowerCaveat = Enforcer.Caveat({
        enforcer: address(borrowerEnforcer),
        salt: bytes32(uint256(2)),
        caveat: abi.encode(caveat),
        approval: Enforcer.Approval({
          v: 0,
          r: bytes32(0),
          s: bytes32(0)
        })
      });

      (borrowerCaveat.approval.v, borrowerCaveat.approval.r, borrowerCaveat.approval.s) = vm.sign(borrower.key, keccak256(abi.encode(borrowerCaveat.enforcer, borrowerCaveat.caveat, borrowerCaveat.salt)));
      
      caveat.loan.borrower = address(0);
      caveat.loan.issuer = lender.addr;
      Enforcer.Caveat memory lenderCaveat = Enforcer.Caveat({
        enforcer: address(lenderEnforcer),
        salt: bytes32(uint256(1)),
        caveat: abi.encode(caveat),
        approval: Enforcer.Approval({
          v: 0,
          r: bytes32(0),
          s: bytes32(0)
        })
      });

      (lenderCaveat.approval.v, lenderCaveat.approval.r, lenderCaveat.approval.s) = vm.sign(lender.key, keccak256(abi.encode(lenderCaveat.enforcer, lenderCaveat.caveat, lenderCaveat.salt)));
      

      loan.borrower = borrower.addr;
      loan.issuer = lender.addr;

      // vm.startPrank(borrower.addr);
      origination.originate(
        new ConduitTransfer[](0),
        borrowerCaveat,
        lenderCaveat,
        loan
      );
    }

    function testNovelOriginationRefinanceForGas() public {
      
      vm.startPrank(borrower.addr);
      erc721s[0].setApprovalForAll(address(origination), true);
      vm.stopPrank();

      vm.startPrank(lender.addr);
      erc20s[0].approve(address(origination), 1);
      vm.stopPrank();
      
      SpentItem[] memory collateral = new SpentItem[](1);
      collateral[0] = SpentItem({
          itemType: ItemType.ERC721,
          token: address(erc721s[0]),
          identifier: 1,
          amount: 1
      });

      SpentItem[] memory debt = new SpentItem[](1);
      debt[0] = SpentItem({
          itemType: ItemType.ERC20,
          token: address(erc20s[0]),
          identifier: 0,
          amount: 1
      });

      LoanManager.Loan memory loan = LoanManager.Loan({
        start: 0,
        custodian: address(custodian),
        borrower: borrower.addr,
        issuer: address(0),
        originator: address(0),
        collateral: collateral,
        debt: debt,
        terms: LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        })
      });

      BaseEnforcer.Details memory caveat = BaseEnforcer.Details({
        loan: loan
      });

      Enforcer.Caveat memory borrowerCaveat = Enforcer.Caveat({
        enforcer: address(borrowerEnforcer),
        salt: bytes32(uint256(2)),
        caveat: abi.encode(caveat),
        approval: Enforcer.Approval({
          v: 0,
          r: bytes32(0),
          s: bytes32(0)
        })
      });

      (borrowerCaveat.approval.v, borrowerCaveat.approval.r, borrowerCaveat.approval.s) = vm.sign(borrower.key, keccak256(abi.encode(borrowerCaveat.enforcer, borrowerCaveat.caveat, borrowerCaveat.salt)));
      
      caveat.loan.borrower = address(0);
      caveat.loan.issuer = lender.addr;
      Enforcer.Caveat memory lenderCaveat = Enforcer.Caveat({
        enforcer: address(lenderEnforcer),
        salt: bytes32(uint256(1)),
        caveat: abi.encode(caveat),
        approval: Enforcer.Approval({
          v: 0,
          r: bytes32(0),
          s: bytes32(0)
        })
      });

      (lenderCaveat.approval.v, lenderCaveat.approval.r, lenderCaveat.approval.s) = vm.sign(lender.key, keccak256(abi.encode(lenderCaveat.enforcer, lenderCaveat.caveat, lenderCaveat.salt)));

      loan.borrower = borrower.addr;
      loan.issuer = lender.addr;

      LoanManager.Loan memory newLoan;
      {
        vm.startPrank(borrower.addr);
        newLoan = origination.originate(
          new ConduitTransfer[](0),
          borrowerCaveat,
          lenderCaveat,
          loan
        );
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(recaller.addr);
        BaseRecall recallContract = BaseRecall(address(hook));
        recallContract.recall(newLoan, recallerConduit);
        vm.stopPrank();

        vm.warp(block.timestamp + 3 days - 1);


        (SpentItem[] memory considerationPayment, SpentItem[] memory carryPayment,) = Pricing(loan.terms.pricing).isValidRefinance(newLoan, defaultPricingData, recaller.addr);
        
        uint256 i=0;
        if(carryPayment.length > 0){
          for(;i<considerationPayment.length;){
            loan.debt[i].amount = considerationPayment[i].amount + carryPayment[i].amount;

            unchecked {
              ++i;
            }
          }
        }
        else {
          for(;i<considerationPayment.length;){
            loan.debt[i].amount = considerationPayment[i].amount;
            unchecked {
              ++i;
            }
          }
        }
      }

      loan.issuer = recaller.addr;
      loan.borrower = address(0);
      loan.originator = address(0);

      caveat.loan = loan;
      Enforcer.Caveat memory recallerCaveat = Enforcer.Caveat({
        enforcer: address(lenderEnforcer),
        salt: bytes32(uint256(1)),
        caveat: abi.encode(caveat),
        approval: Enforcer.Approval({
          v: 0,
          r: bytes32(0),
          s: bytes32(0)
        })
      });

      (recallerCaveat.approval.v, recallerCaveat.approval.r, recallerCaveat.approval.s) = vm.sign(recaller.key, keccak256(abi.encode(recallerCaveat.enforcer, recallerCaveat.caveat, recallerCaveat.salt)));

      vm.startPrank(recaller.addr);
      erc20s[0].approve(address(origination), loan.debt[0].amount);
      // vm.stopPrank();
      origination.refinance(
        recaller.addr,
        recallerCaveat,
        newLoan,
        defaultPricingData
      );
      vm.stopPrank();
    }
}
