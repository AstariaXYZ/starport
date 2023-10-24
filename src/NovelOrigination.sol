pragma solidity =0.8.17;
import {LoanManager} from "starport-core/LoanManager.sol";
// import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {Enforcer} from "starport-core/Enforcer.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {SpentItem, ItemType, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";

contract NovelOrigination {
  error NativeAssetsNotSupported();
  error HashAlreadyInvalidated();
  error InvalidItemType();
  error UnauthorizedAdditionalTransferIncluded();
  error InvalidCaveatSigner();
  error MalformedRefinance();

  LoanManager LM;

  mapping(address => mapping(bytes32 => bool)) invalidHashes;
  mapping(address => mapping(address => bool)) approvals;
  constructor(LoanManager LM_){
    LM = LM_;
  }

  function originate(
    ConduitTransfer[] calldata additionalTransfers,
    Enforcer.Caveat calldata borrowerCaveat,
    Enforcer.Caveat calldata lenderCaveat,
    LoanManager.Loan memory loan) external payable returns (LoanManager.Loan memory){

    if(msg.sender != loan.borrower){
      _validateAndEnforceCaveats(borrowerCaveat, loan.borrower, additionalTransfers, loan);
    }

    if(msg.sender != loan.issuer && !approvals[loan.issuer][msg.sender]){
      _validateAndEnforceCaveats(lenderCaveat, loan.issuer, additionalTransfers, loan);
    }

    _transferSpentItems(loan.debt, loan.issuer, loan.borrower);
    _transferSpentItems(loan.collateral, loan.borrower, loan.custodian);

    
    if(additionalTransfers.length > 0){
      _validateAdditionalTransfers(loan.borrower, loan.issuer, msg.sender, additionalTransfers);
      _transferConduitTransfers(additionalTransfers);
    }

    loan.start = block.timestamp;
    //mint LM
    LM.issueLoanManager(loan, true);
    return loan;
  }

  function refinance(
      address lender,
      Enforcer.Caveat calldata lenderCaveat,
      LoanManager.Loan memory loan,
      bytes memory pricingData
      ) external
  {
    (
        SpentItem[] memory considerationPayment,
        SpentItem[] memory carryPayment,
        ConduitTransfer[] memory additionalTransfers
    ) = Pricing(loan.terms.pricing).isValidRefinance(loan, pricingData, msg.sender);


    if(considerationPayment.length == 0 || (carryPayment.length != 0 && considerationPayment.length != carryPayment.length) || considerationPayment.length != loan.debt.length) {
      revert MalformedRefinance();
    }
    LM.settle(loan);

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

    loan.terms.pricingData = pricingData;
    
    _transferSpentItems(considerationPayment, lender, loan.issuer);
    _transferSpentItems(carryPayment, lender, loan.originator);

    loan.issuer = lender;
    loan.originator = address(0);
    loan.start = 0;

    if(msg.sender != loan.issuer && !approvals[loan.issuer][msg.sender]){
      _validateAndEnforceCaveats(lenderCaveat, loan.issuer, additionalTransfers, loan);
    }

    if(additionalTransfers.length > 0){
      _validateAdditionalTransfers(loan.borrower, loan.issuer, msg.sender, additionalTransfers);
      _transferConduitTransfers(additionalTransfers);
    }

    loan.originator = msg.sender;
    loan.start = block.timestamp;

    LM.issueLoanManager(loan, msg.sender.code.length > 0);
  }

  function _validateAdditionalTransfers(address borrower, address lender, address fulfiller, ConduitTransfer[] memory additionalTransfers) internal pure {
    uint256 i = 0;
    for(i; i<additionalTransfers.length;){
      if(additionalTransfers[i].from != borrower && additionalTransfers[i].from != lender && additionalTransfers[i].from != fulfiller) revert UnauthorizedAdditionalTransferIncluded();
      unchecked {
        ++i;
      }
    }
  }
  function _validateAndEnforceCaveats(Enforcer.Caveat memory caveat, address validator, ConduitTransfer[] memory additionalTransfers, LoanManager.Loan memory loan) internal {
    bytes32 salt = caveat.salt;
    if(salt != bytes32(0)){
      if(invalidHashes[validator][salt]){
        revert HashAlreadyInvalidated();
      }
      else{
        if(salt != bytes32(0)) invalidHashes[validator][salt] = true;
      }
    }

    bytes32 hash = keccak256(abi.encode(caveat.enforcer, caveat.caveat, salt));
    address signer = ecrecover(hash, caveat.approval.v, caveat.approval.r, caveat.approval.s);
    if(signer != validator) revert InvalidCaveatSigner();

    // will revert if invalid
    Enforcer(caveat.enforcer).validate(additionalTransfers, loan, caveat.caveat);
  }

  function _transferConduitTransfers(ConduitTransfer[] memory transfers) internal {
      uint256 i=0;
      for(i; i<transfers.length;){
        if(transfers[i].amount != 0){
          if(transfers[i].itemType == ConduitItemType.ERC20){
            // erc20 transfer
            ERC20(transfers[i].token).transferFrom(transfers[i].from, transfers[i].to, transfers[i].amount);
          }
          else if(transfers[i].itemType == ConduitItemType.ERC721){
            // erc721 transfer
            ERC721(transfers[i].token).transferFrom(transfers[i].from, transfers[i].to, transfers[i].identifier);
          }
          else if(transfers[i].itemType == ConduitItemType.ERC1155){
            // erc1155 transfer
            ERC1155(transfers[i].token).safeTransferFrom(transfers[i].from, transfers[i].to, transfers[i].identifier, transfers[i].amount, new bytes(0));
          }
          else revert NativeAssetsNotSupported();

        }
        unchecked {
          ++i;
        }
      }
  }

  function _transferSpentItems(SpentItem[] memory transfers, address from, address to) internal {
    uint256 i=0;
    for(i; i<transfers.length;){
      if(transfers[i].amount != 0){
        if(transfers[i].itemType == ItemType.ERC20){
          // erc20 transfer
          ERC20(transfers[i].token).transferFrom(from, to, transfers[i].amount);
        }
        else if(transfers[i].itemType == ItemType.ERC721){
          // erc721 transfer
          ERC721(transfers[i].token).transferFrom(from, to, transfers[i].identifier);
        }
        else if(transfers[i].itemType == ItemType.ERC1155){
          // erc1155 transfer
          ERC1155(transfers[i].token).safeTransferFrom(from, to, transfers[i].identifier, transfers[i].amount, new bytes(0));
        }
        else revert NativeAssetsNotSupported();
      }
      unchecked {
        ++i;
      }
    }
  }
}