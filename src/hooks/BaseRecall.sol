// SPDX-License-Identifier: BUSL-1.1
/**
 *                                                                                                                           ,--,
 *                                                                                                                        ,---.'|
 *      ,----..    ,---,                                                                            ,-.                   |   | :
 *     /   /   \ ,--.' |                  ,--,                                                  ,--/ /|                   :   : |                 ,---,
 *    |   :     :|  |  :                ,--.'|         ,---,          .---.   ,---.    __  ,-.,--. :/ |                   |   ' :               ,---.'|
 *    .   |  ;. /:  :  :                |  |,      ,-+-. /  |        /. ./|  '   ,'\ ,' ,'/ /|:  : ' /  .--.--.           ;   ; '               |   | :     .--.--.
 *    .   ; /--` :  |  |,--.  ,--.--.   `--'_     ,--.'|'   |     .-'-. ' | /   /   |'  | |' ||  '  /  /  /    '          '   | |__   ,--.--.   :   : :    /  /    '
 *    ;   | ;    |  :  '   | /       \  ,' ,'|   |   |  ,"' |    /___/ \: |.   ; ,. :|  |   ,''  |  : |  :  /`./          |   | :.'| /       \  :     |,-.|  :  /`./
 *    |   : |    |  |   /' :.--.  .-. | '  | |   |   | /  | | .-'.. '   ' .'   | |: :'  :  /  |  |   \|  :  ;_            '   :    ;.--.  .-. | |   : '  ||  :  ;_
 *    .   | '___ '  :  | | | \__\/: . . |  | :   |   | |  | |/___/ \:     ''   | .; :|  | '   '  : |. \\  \    `.         |   |  ./  \__\/: . . |   |  / : \  \    `.
 *    '   ; : .'||  |  ' | : ," .--.; | '  : |__ |   | |  |/ .   \  ' .\   |   :    |;  : |   |  | ' \ \`----.   \        ;   : ;    ," .--.; | '   : |: |  `----.   \
 *    '   | '/  :|  :  :_:,'/  /  ,.  | |  | '.'||   | |--'   \   \   ' \ | \   \  / |  , ;   '  : |--'/  /`--'  /        |   ,/    /  /  ,.  | |   | '/ : /  /`--'  /
 *    |   :    / |  | ,'   ;  :   .'   \;  :    ;|   |/        \   \  |--"   `----'   ---'    ;  |,'  '--'.     /         '---'    ;  :   .'   \|   :    |'--'.     /
 *     \   \ .'  `--''     |  ,     .-./|  ,   / '---'          \   \ |                       '--'      `--'---'                   |  ,     .-.//    \  /   `--'---'
 *      `---`               `--`---'     ---`-'                  '---"                                                              `--`---'    `-'----'
 *
 * Chainworks Labs
 */
pragma solidity ^0.8.17;

import "forge-std/console2.sol";

import {LoanManager} from "starport-core/LoanManager.sol";
import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";

import {BasePricing} from "starport-core/pricing/BasePricing.sol";

import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";

import {ConduitControllerInterface} from "seaport-sol/src/ConduitControllerInterface.sol";

import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {AdditionalTransfer} from "starport-core/lib/StarPortLib.sol";

import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";

import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";

abstract contract BaseRecall {
    using FixedPointMathLib for uint256;
    using {StarPortLib.getId} for LoanManager.Loan;

    event Recalled(uint256 loandId, address recaller, uint256 end);
    event Withdraw(uint256 loanId, address withdrawer);

    LoanManager public immutable LM;

    error InvalidWithdraw();
    error InvalidConduit();
    error AdditionalTransferError();
    error InvalidStakeType();
    error LoanDoesNotExist();
    error RecallBeforeHoneymoonExpiry();
    error LoanHasNotBeenRefinanced();
    error WithdrawDoesNotExist();
    error InvalidItemType();

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

    function recall(LoanManager.Loan calldata loan) external {
        Details memory details = abi.decode(loan.terms.hookData, (Details));

        if ((loan.start + details.honeymoon) > block.timestamp) {
            revert RecallBeforeHoneymoonExpiry();
        }

        if (loan.issuer != msg.sender && loan.borrower != msg.sender) {
            // (,, address conduitController) = LM.seaport().information();
            // validate that the provided conduit is owned by the msg.sender
            // if (ConduitControllerInterface(conduitController).ownerOf(conduit) != msg.sender) {
            //     revert InvalidConduit();
            // }
            AdditionalTransfer[] memory recallConsideration = _generateRecallConsideration(
                loan, 0, details.recallStakeDuration, 1e18, msg.sender, payable(address(this))
            );
            StarPortLib.transferAdditionalTransfers(recallConsideration);
        }
        // get conduitController

        bytes memory encodedLoan = abi.encode(loan);

        uint256 loanId = uint256(keccak256(encodedLoan));

        if (!LM.active(loanId)) revert LoanDoesNotExist();

        recalls[loanId] = Recall(payable(msg.sender), uint64(block.timestamp));
        emit Recalled(loanId, msg.sender, loan.start + details.recallWindow);
    }

    // transfers all stake to anyone who asks after the LM token is burned
    function withdraw(LoanManager.Loan calldata loan, address payable receiver) external {
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

        if (loan.issuer != recall.recaller && loan.borrower != recall.recaller) {
            AdditionalTransfer[] memory recallConsideration =
                _generateRecallConsideration(loan, 0, details.recallStakeDuration, 1e18, address(this), receiver);
            recall.recaller = payable(address(0));
            recall.start = 0;

            for (uint256 i; i < recallConsideration.length;) {
                if (loan.debt[i].itemType != ItemType.ERC20) revert InvalidStakeType();

                ERC20(loan.debt[i].token).transfer(receiver, recallConsideration[i].amount);

                unchecked {
                    ++i;
                }
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
            recallStake[i] = BasePricing(loan.terms.pricing).getInterest(loan, details.rate, start, end, i);

            unchecked {
                ++i;
            }
        }
    }

    function generateRecallConsideration(
        LoanManager.Loan calldata loan,
        uint256 proportion,
        address from,
        address payable to
    ) external view returns (AdditionalTransfer[] memory consideration) {
        Details memory details = abi.decode(loan.terms.hookData, (Details));
        return _generateRecallConsideration(loan, 0, details.recallStakeDuration, proportion, from, to);
    }

    function _generateRecallConsideration(
        LoanManager.Loan calldata loan,
        uint256 start,
        uint256 end,
        uint256 proportion,
        address from,
        address payable to
    ) internal view returns (AdditionalTransfer[] memory additionalTransfers) {
        uint256[] memory stake = _getRecallStake(loan, start, end);
        additionalTransfers = new AdditionalTransfer[](stake.length);

        for (uint256 i; i < additionalTransfers.length;) {
            additionalTransfers[i] = AdditionalTransfer({
                itemType: loan.debt[i].itemType,
                identifier: loan.debt[i].identifier,
                amount: stake[i].mulWad(proportion),
                token: loan.debt[i].token,
                from: from,
                to: to
            });
            unchecked {
                ++i;
            }
        }
    }
}
