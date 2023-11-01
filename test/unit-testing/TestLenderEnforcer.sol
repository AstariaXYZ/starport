import "starport-test/StarPortTest.sol";
import {LenderEnforcer} from "starport-core/enforcers/LenderEnforcer.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";

import "forge-std/console.sol";

contract TestLenderEnforcer is StarPortTest {
    function testLERevertAdditionalTransfersFromLender() external {
        ConduitTransfer[] memory additionalTransfers = new ConduitTransfer[](1);
        additionalTransfers[0] = ConduitTransfer({
            token: address(0),
            amount: 0,
            to: address(0),
            from: lender.addr,
            identifier: 0,
            itemType: ConduitItemType.ERC20
        });

        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        vm.expectRevert(LenderEnforcer.InvalidAdditionalTransfer.selector);
        lenderEnforcer.validate(additionalTransfers, loan, abi.encode(LenderEnforcer.Details({loan: loan})));
    }

    function testLERevertInvalidLoanTerms() external {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        LenderEnforcer.Details memory details = LenderEnforcer.Details({loan: loan});
        details.loan.custodian = borrower.addr;
        vm.expectRevert(LenderEnforcer.InvalidLoanTerms.selector);

        lenderEnforcer.validate(new ConduitTransfer[](0), generateDefaultLoanTerms(), abi.encode(details));
    }

    function testLEValidLoanTermsWithAdditionalTransfers() external view {
        ConduitTransfer[] memory additionalTransfers = new ConduitTransfer[](1);
        additionalTransfers[0] = ConduitTransfer({
            token: address(0),
            amount: 0,
            to: address(0),
            from: address(0),
            identifier: 0,
            itemType: ConduitItemType.ERC20
        });
        LoanManager.Loan memory loan = generateDefaultLoanTerms();
        lenderEnforcer.validate(additionalTransfers, loan, abi.encode(LenderEnforcer.Details({loan: loan})));
    }

    function testLEValidLoanTerms() external view {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();
        lenderEnforcer.validate(new ConduitTransfer[](0), loan, abi.encode(LenderEnforcer.Details({loan: loan})));
    }

    function testLEValidLoanTermsAnyBorrower() external view {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();
        LenderEnforcer.Details memory details = LenderEnforcer.Details({loan: loan});
        details.loan.borrower = address(0);

        lenderEnforcer.validate(new ConduitTransfer[](0), loan, abi.encode(LenderEnforcer.Details({loan: loan})));
    }
}
