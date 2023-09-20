pragma solidity =0.8.17;

import "forge-std/console2.sol";

import {LoanManager} from "src/LoanManager.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

import {BasePricing} from "src/pricing/BasePricing.sol";

import {ConduitHelper} from "src/ConduitHelper.sol";

import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {ConduitControllerInterface} from "seaport-sol/src/ConduitControllerInterface.sol";

import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";

import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {StarPortLib} from "src/lib/StarPortLib.sol";

abstract contract BaseRecall is ConduitHelper {
    using FixedPointMathLib for uint256;
    using {StarPortLib.getId} for LoanManager.Loan;

    event Recalled(uint256 loandId, address recaller, uint256 end);
    event Withdraw(uint256 loanId, address withdrawer);

    LoanManager LM;

    error InvalidWithdraw();
    error InvalidConduit();
    error ConduitTransferError();
    error InvalidStakeType();
    error LoanDoesNotExist();
    error RecallBeforeHoneymoonExpiry();
    error LoanHasNotBeenRefinanced();
    error WithdrawDoesNotExist();

    ConsiderationInterface public constant seaport = ConsiderationInterface(0x2e234DAe75C793f67A35089C9d99245E1C58470b);
    mapping(uint256 => Recall) public recalls;

    struct Details {
        // period at the begininng of a loan in which the loan cannot be recalled
        uint256 honeymoon;
        // period for which the recall is active
        uint256 recallWindow;
        // days of interest a recaller must stake
        uint256 recallStakeDuration;
        // maximum rate of the recall before failure
        uint256 recallMax;
        // ratio the recaller gets at liquidation (1e18, 100%, 1.0)
        uint256 recallerRewardRatio;
    }

    struct Recall {
        address payable recaller;
        uint64 start;
    }

    constructor(LoanManager LM_) {
        LM = LM_;
    }

    function getRecallRate(LoanManager.Loan calldata loan) external view returns (uint256) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        uint256 loanId = loan.getId();
        // calculates the porportion of time elapsed, then multiplies times the max rate
        return details.recallMax.mulWad((block.timestamp - recalls[loanId].start).divWad(details.recallWindow));
    }

    function recall(LoanManager.Loan memory loan, address conduit) external {
        Details memory details = abi.decode(loan.terms.hookData, (Details));

        if ((loan.start + details.honeymoon) > block.timestamp) {
            revert RecallBeforeHoneymoonExpiry();
        }

        // get conduitController
        (,, address conduitController) = seaport.information();
        // validate that the provided conduit is owned by the msg.sender
        if (ConduitControllerInterface(conduitController).ownerOf(conduit) != msg.sender) {
            revert InvalidConduit();
        }
        ReceivedItem[] memory recallConsideration =
            _generateRecallConsideration(loan, 0, details.recallStakeDuration, 1e18, payable(address(this)));
        if (
            ConduitInterface(conduit).execute(_packageTransfers(recallConsideration, msg.sender))
                != ConduitInterface.execute.selector
        ) {
            revert ConduitTransferError();
        }

        bytes memory encodedLoan = abi.encode(loan);

        uint256 loanId = uint256(keccak256(encodedLoan));

        if (!LM.active(loanId)) revert LoanDoesNotExist();

        recalls[loanId] = Recall(payable(msg.sender), uint64(block.timestamp));
        emit Recalled(loanId, msg.sender, loan.start + details.recallWindow);
    }

    // transfers all stake to anyone who asks after the LM token is burned
    function withdraw(LoanManager.Loan memory loan, address payable receiver) external {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        bytes memory encodedLoan = abi.encode(loan);
        uint256 loanId = uint256(keccak256(encodedLoan));

        // loan has not been refinanced, loan is still active. LM.tokenId changes on refinance
        if (!LM.inactive(loanId)) revert LoanHasNotBeenRefinanced();

        Recall storage recall = recalls[loanId];
        // ensure that a recall exists for the provided tokenId, ensure that the recall
        if (recall.start == 0 || recall.recaller == address(0)) {
            revert WithdrawDoesNotExist();
        }

        ReceivedItem[] memory recallConsideration =
            _generateRecallConsideration(loan, 0, details.recallStakeDuration, 1e18, receiver);
        recall.recaller = payable(address(0));
        recall.start = 0;

        for (uint256 i; i < recallConsideration.length;) {
            if (loan.debt[i].itemType != ItemType.ERC20) revert InvalidStakeType();

            ERC20(loan.debt[i].token).transfer(receiver, recallConsideration[i].amount);

            unchecked {
                ++i;
            }
        }

        emit Withdraw(loanId, receiver);
    }

    function _getRecallStake(LoanManager.Loan memory loan, uint256 start, uint256 end)
        internal
        view
        returns (uint256[] memory recallStake)
    {
        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        recallStake = new uint256[](loan.debt.length);
        for (uint256 i; i < loan.debt.length;) {
            recallStake[i] = BasePricing(loan.terms.pricing).getInterest(loan, details, start, end, i);

            unchecked {
                ++i;
            }
        }
    }

    function generateRecallConsideration(LoanManager.Loan memory loan, uint256 proportion, address payable receiver)
        external
        view
        returns (ReceivedItem[] memory consideration)
    {
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

        for (uint256 i; i < consideration.length;) {
            consideration[i] = ReceivedItem({
                itemType: loan.debt[i].itemType,
                identifier: loan.debt[i].identifier,
                amount: stake[i].mulWad(proportion),
                token: loan.debt[i].token,
                recipient: receiver
            });
            unchecked {
                ++i;
            }
        }
    }
}
