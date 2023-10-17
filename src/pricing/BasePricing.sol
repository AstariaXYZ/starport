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
pragma solidity =0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import "forge-std/console2.sol";

import {BaseHook} from "starport-core/hooks/BaseHook.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";

abstract contract BasePricing is Pricing {
    using FixedPointMathLib for uint256;
    using {StarPortLib.getId} for LoanManager.Loan;

    struct Details {
        uint256 rate;
        uint256 carryRate;
    }

    function getPaymentConsideration(LoanManager.Loan memory loan)
        public
        view
        virtual
        override
        returns (ReceivedItem[] memory repayConsideration, ReceivedItem[] memory carryConsideration)
    {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));

        uint256 length = loan.debt.length;
        repayConsideration = new ReceivedItem[](length);

        uint256 delta_t = block.timestamp - loan.start;

        if (details.carryRate != 0) {
            carryConsideration = new ReceivedItem[](length);
            for (uint256 i = 0; i < length;) {
                uint256 interest = calculateInterest(delta_t, loan.debt[i].amount, details.rate);
                uint256 carry = interest.divWad(details.carryRate);
                repayConsideration[i] = ReceivedItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: loan.debt[i].amount + interest - carry,
                    token: loan.debt[i].token,
                    recipient: payable(loan.issuer)
                });

                carryConsideration[i] = ReceivedItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: carry,
                    token: loan.debt[i].token,
                    recipient: payable(loan.originator)
                });
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i = 0; i < length;) {
                uint256 interest = calculateInterest(delta_t, loan.debt[i].amount, details.rate);
                repayConsideration[i] = ReceivedItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: loan.debt[i].amount + interest,
                    token: loan.debt[i].token,
                    recipient: payable(loan.issuer)
                });

                unchecked {
                    ++i;
                }
            }
        }
    }

    function getInterest(
        LoanManager.Loan memory loan,
        Details memory details,
        uint256 start,
        uint256 end,
        uint256 index
    ) public pure returns (uint256) {
        uint256 delta_t = end - start;
        return calculateInterest(delta_t, details.rate, loan.debt[index].amount);
    }

    function calculateInterest(
        uint256 delta_t,
        uint256 amount,
        uint256 rate // expressed as SPR seconds per rate
    ) public pure virtual returns (uint256);
}
