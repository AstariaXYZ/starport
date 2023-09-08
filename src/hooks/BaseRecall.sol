pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

import {BasePricing} from "src/pricing/BasePricing.sol";

import {ConduitHelper} from "src/ConduitHelper.sol";

import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {
  ConduitControllerInterface
} from "seaport-sol/src/ConduitControllerInterface.sol";

import {
  ConsiderationInterface
} from "seaport-types/src/interfaces/ConsiderationInterface.sol";

import {
  ConduitInterface
} from "seaport-types/src/interfaces/ConduitInterface.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

abstract contract BaseRecall is ConduitHelper {
  using FixedPointMathLib for uint256;

  LoanManager LM;
  error InvalidWithdraw();
  error InvalidConduit();
  error ConduitTransferError();
  error InvalidStakeType();
  error LoanDoesNotExist();

  ConsiderationInterface public constant seaport =
  ConsiderationInterface(0x2e234DAe75C793f67A35089C9d99245E1C58470b);
  mapping(uint256 => Recall) recalls;
  struct Details {
      // period at the begininng of a loan in which the loan cannot be recalled
      uint256 honeymoon;
      // period for which the recall is active
      uint256 recallWindow;
      // days of interest a recaller must stake
      uint256 recallStakeDuration;
      // maximum rate of the recall before failure
      uint256 recallMax;
  }

  struct Recall {
    address recaller;
    uint64 start;
  }

  function getRecallRate(LoanManager.Loan calldata loan) view external returns (uint256) {
    Details memory details = abi.decode(loan.terms.hookData, (Details));
    uint256 tokenId = LM.getTokenIdFromLoan(loan);
    // calculates the porportion of time elapsed, then multiplies times the max rate
    return details.recallMax.mulWad((block.timestamp - recalls[tokenId].start).divWad(details.recallWindow)); 
  }

  function recall(LoanManager.Loan calldata loan, address conduit) external {
    Details memory details = abi.decode(loan.terms.hookData, (Details));
    if(loan.start + details.honeymoon < block.timestamp) {
      revert("recall before honeymoon ended");
    }
    // valdiate that the recaller is not the borrower
    if(msg.sender != loan.borrower){
      // get conduitController
      (, , address conduitController) = seaport.information();
      // validate that the provded conduit is owned by the msg.sender
      if (
        ConduitControllerInterface(conduitController).ownerOf(conduit) !=
        msg.sender
      ) {
        revert InvalidConduit();
      }
      ReceivedItem[] memory recallConsideration = _generateRecallConsideration(loan, 0, details.recallStakeDuration, 1e18, payable(address(this)));
      if (
        ConduitInterface(conduit).execute(
          _packageTransfers(recallConsideration, msg.sender)
        ) != ConduitInterface.execute.selector
      ) {
        revert ConduitTransferError();
      }
    }
    
    uint256 tokenId = LM.getTokenIdFromLoan(loan);
    if(LM.ownerOf(tokenId) == address(0)) revert LoanDoesNotExist();
    recalls[tokenId] = Recall(msg.sender, uint64(block.timestamp));
  }

  // transfers all stake to anyone who asks after the LM token is burned
  function withdraw(LoanManager.Loan memory loan, address payable receiver) external {
    Details memory details = abi.decode(loan.terms.pricingData, (Details));
    uint256 tokenId = LM.getTokenIdFromLoan(loan);

    // loan has not been refinanced, loan is still active. LM.tokenId changes on refinance
    if(LM.ownerOf(tokenId) != address(0)) revert InvalidWithdraw();

    Recall storage recall = recalls[tokenId];
    // ensure that a recall exists for the provided tokenId, ensure that the recall was not the borrower (borrowers do not need to provide stake to recall)
    if(recall.start == 0 && recall.recaller != loan.borrower) revert InvalidWithdraw();
    ReceivedItem[] memory recallConsideration = _generateRecallConsideration(loan, 0, details.recallWindow, 1e18, receiver);
    recall.recaller = address(0);
    recall.start = 0;

    uint256 i = 0;
    for (; i < recallConsideration.length; ) {
      if(loan.debt[i].itemType != ItemType.ERC20) revert InvalidStakeType();
      ERC20(loan.debt[i].token).transfer(receiver, recallConsideration[i].amount);
      unchecked {
        ++i;
      }
    }
  }

  function _getRecallStake(
    LoanManager.Loan memory loan,
    uint256 start,
    uint256 end
  ) internal view returns (uint256[] memory recallStake) {
    BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
    recallStake = new uint256[](loan.debt.length);
    uint256 i = 0;
    for (; i < loan.debt.length; ) {
      uint256 delta_t = end - start;
      uint256 stake = BasePricing(loan.terms.pricing).getInterest(loan, details, start, end, i);
      recallStake[i] = stake;
    }
  }

  function generateRecallConsideration(
    LoanManager.Loan memory loan,
    uint256 proportion,
    address payable receiver
  ) external view returns (ReceivedItem[] memory consideration) {
    Details memory details = abi.decode(loan.terms.hookData, (Details));
    return _generateRecallConsideration(loan, 0, details.recallStakeDuration, 1e18, receiver);
  }

  function _generateRecallConsideration(
    LoanManager.Loan memory loan,
    uint256 start,
    uint256 end,
    uint256 proportion,
    address payable receiver
  ) internal view returns (ReceivedItem[] memory consideration) {

    uint256[] memory stake = _getRecallStake(loan, start, end);
    consideration = new ReceivedItem[](stake.length);
    uint256 i = 0;
    for (; i < consideration.length; ) {
      consideration[i] = ReceivedItem({
        itemType: loan.debt[i].itemType,
        identifier: loan.debt[i].identifier,
        amount: stake.length == consideration.length ? stake[i].mulWad(proportion) : stake[0].mulWad(proportion),
        token: loan.debt[i].token,
        recipient: receiver
      });
      unchecked {
        ++i;
      }
    }
  }
}