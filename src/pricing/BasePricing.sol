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

import {Starport} from "starport-core/Starport.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Status} from "starport-core/status/Status.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

import {StarportLib} from "starport-core/lib/StarportLib.sol";
import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract BasePricing is Pricing {
    using FixedPointMathLib for uint256;
    using {StarportLib.getId} for Starport.Loan;

    struct Details {
        uint256 rate;
        uint256 carryRate;
        uint256 decimals;
    }

    function getPaymentConsideration(Starport.Loan memory loan)
        public
        view
        virtual
        override
        returns (SpentItem[] memory repayConsideration, SpentItem[] memory carryConsideration)
    {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));
        if (details.carryRate > 0 && loan.issuer != loan.originator) {
            carryConsideration = new SpentItem[](loan.debt.length);
        } else {
            carryConsideration = new SpentItem[](0);
        }
        repayConsideration = new SpentItem[](loan.debt.length);

        uint256 i = 0;
        for (; i < loan.debt.length;) {
            uint256 interest = getInterest(loan, details.rate, loan.start, block.timestamp, i, details.decimals);

            if (carryConsideration.length > 0) {
                carryConsideration[i] = SpentItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: (interest * details.carryRate) / 10 ** details.decimals,
                    token: loan.debt[i].token
                });
                repayConsideration[i] = SpentItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: loan.debt[i].amount + interest - carryConsideration[i].amount,
                    token: loan.debt[i].token
                });
            } else {
                repayConsideration[i] = SpentItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: loan.debt[i].amount + interest,
                    token: loan.debt[i].token
                });
            }
            unchecked {
                ++i;
            }
        }
    }

    function validate(Starport.Loan calldata loan) external pure virtual override returns (bytes4) {
        return Pricing.validate.selector;
    }

    function getInterest(
        Starport.Loan memory loan,
        uint256 rate,
        uint256 start,
        uint256 end,
        uint256 index,
        uint256 decimals
    ) public pure returns (uint256) {
        uint256 delta_t = end - start;
        return calculateInterest(delta_t, loan.debt[index].amount, rate, decimals);
    }

    function calculateInterest(uint256 delta_t, uint256 amount, uint256 rate, uint256 decimals)
        public
        pure
        virtual
        returns (uint256);
}
