import "starport-test/StarPortTest.sol";
import {BorrowerEnforcer} from "starport-core/enforcers/BorrowerEnforcer.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";

import "forge-std/console.sol";

contract TestBorrowerEnforcer is StarPortTest {
    function testBERevertAdditionalTransfers() external {
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
        BorrowerEnforcer.Details memory details = BorrowerEnforcer.Details({loan: loan});
        vm.expectRevert(BorrowerEnforcer.InvalidAdditionalTransfer.selector);
        borrowerEnforcer.validate(additionalTransfers, loan, abi.encode(details));
    }

    function testBERevertInvalidLoanTerms() external {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();

        BorrowerEnforcer.Details memory details = BorrowerEnforcer.Details({loan: loan});
        details.loan.borrower = lender.addr;
        vm.expectRevert(BorrowerEnforcer.InvalidLoanTerms.selector);
        borrowerEnforcer.validate(new ConduitTransfer[](0), generateDefaultLoanTerms(), abi.encode(details));
    }

    function testBEValidLoanTerms() external view {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();
        borrowerEnforcer.validate(new ConduitTransfer[](0), loan, abi.encode(BorrowerEnforcer.Details({loan: loan})));
    }

    function testBEValidLoanTermsAnyIssuer() external view {
        LoanManager.Loan memory loan = generateDefaultLoanTerms();
        BorrowerEnforcer.Details memory details = BorrowerEnforcer.Details({loan: loan});
        details.loan.issuer = address(0);

        borrowerEnforcer.validate(new ConduitTransfer[](0), loan, abi.encode(BorrowerEnforcer.Details({loan: loan})));
    }
}
