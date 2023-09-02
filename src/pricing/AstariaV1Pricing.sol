pragma solidity =0.8.17;
import {LoanManager} from "src/LoanManager.sol";
import {CompoundInterestPricing} from "src/pricing/CompoundInterestPricing.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {BasePricing} from "src/pricing/BasePricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
contract AstariaV1Pricing is CompoundInterestPricing {
  struct Sponsorship {
    uint256 frequency;
    uint256 maxRate;
    bool onRecall;
    bool isAllowed;
  }
  mapping(address => uint256) public deposits;
  event Deposit(address indexed depositor, uint256 amount);
  event Withdraw(address indexed withdrawer, address indexed sponsor, uint256 amount);
  constructor(LoanManager LM_) Pricing(LM_) {}

  // ensures the sponsored gas constrainsts are met before invoking super
  function isValidRefinance(
    LoanManager.Loan memory loan,
    bytes memory newPricingData
  )
    public
    override
    returns (ReceivedItem[] memory, ReceivedItem[] memory)
  {
    Sponsorship memory oldSponsorship;
    BasePricing.Details memory oldDetails;
    (oldSponsorship, oldDetails) = abi.decode(loan.terms.pricingData, (Sponsorship, BasePricing.Details));


    Sponsorship memory newSponsorship;
    BasePricing.Details memory newDetails;
    (newSponsorship, newDetails) = abi.decode(newPricingData, (Sponsorship, BasePricing.Details));
      
    if(oldSponsorship.isAllowed && 
      // ensure the loan refinance is within the frequency
      ((loan.start + oldSponsorship.frequency < block.timestamp) ||
      // ensure that the maxRate condition is met (if the rate exceeds an upper bound)
      // and
      // ensures that the new rate is below the maxRate value
      (oldDetails.rate > oldSponsorship.maxRate && newDetails.rate <= oldSponsorship.maxRate) ||
      // ensures that the loan is being recalled 
      (SettlementHook(loan.terms.hook).isRecalled(loan) && oldSponsorship.onRecall))){
        _refundGas(loan.borrower);
    }
    if(oldSponsorship.frequency != newSponsorship.frequency ||
      oldSponsorship.maxRate != newSponsorship.maxRate ||
      oldSponsorship.onRecall != newSponsorship.onRecall ||
      oldSponsorship.isAllowed != newSponsorship.isAllowed){
      revert("sponsorship mismatch");
    }
    super.isValidRefinance(loan, abi.encode(newDetails));
  }

  function _refundGas(address sponsor) internal {

      uint256 balance = deposits[sponsor];
      require(balance > 0, "Balance must be greater than 0");

      // Calculate the gas fees (gas used * gas price)
      uint256 gasFees = (gasleft() * tx.gasprice) * 3;
      uint256 amount = balance < gasFees ? balance : gasFees;
      require(amount > 0, "Amount must be greater than 0");

      // Update the balance
      deposits[sponsor] -= amount;

      // Transfer the funds
      payable(tx.origin).transfer(amount);

      // Emit the withdraw event
      emit Withdraw(tx.origin, sponsor, amount);
  }

  function deposit() public payable {
      require(msg.value > 0, "Amount must be greater than 0");
      
      // Record the deposit
      deposits[msg.sender] += msg.value;

      // Emit the deposit event
      emit Deposit(msg.sender, msg.value);
  }
}

