import "starport-test/StarportTest.sol";
import {BorrowerEnforcer} from "starport-core/enforcers/BorrowerEnforcer.sol";
import {AdditionalTransfer, ItemType} from "starport-core/lib/StarportLib.sol";

import "forge-std/console.sol";

contract TestBorrowerEnforcer is StarportTest {
    function testBERevertAdditionalTransfersFromBorrower() external {
        AdditionalTransfer[] memory additionalTransfers = new AdditionalTransfer[](1);
        additionalTransfers[0] = AdditionalTransfer({
            token: address(0),
            amount: 0,
            to: address(0),
            from: borrower.addr,
            identifier: 0,
            itemType: ItemType.ERC20
        });

        Starport.Loan memory loan = generateDefaultLoanTerms();
        BorrowerEnforcer.Details memory details = BorrowerEnforcer.Details({loan: loan});
        vm.expectRevert(BorrowerEnforcer.InvalidAdditionalTransfer.selector);
        borrowerEnforcer.validate(additionalTransfers, loan, abi.encode(details));
    }

    function testBERevertInvalidLoanTerms() external {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        BorrowerEnforcer.Details memory details = BorrowerEnforcer.Details({loan: loan});
        details.loan.borrower = lender.addr;
        vm.expectRevert(BorrowerEnforcer.InvalidLoanTerms.selector);
        borrowerEnforcer.validate(new AdditionalTransfer[](0), generateDefaultLoanTerms(), abi.encode(details));
    }

    function testBEValidLoanTerms() external view {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        borrowerEnforcer.validate(new AdditionalTransfer[](0), loan, abi.encode(BorrowerEnforcer.Details({loan: loan})));
    }

    function testBEValidLoanTermsAnyIssuer() external view {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        BorrowerEnforcer.Details memory details = BorrowerEnforcer.Details({loan: loan});
        details.loan.issuer = address(0);

        borrowerEnforcer.validate(new AdditionalTransfer[](0), loan, abi.encode(BorrowerEnforcer.Details({loan: loan})));
    }
}
