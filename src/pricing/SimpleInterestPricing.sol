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

import {ReceivedItem, BasePricing} from "starport-core/pricing/BasePricing.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Starport} from "starport-core/Starport.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {AdditionalTransfer} from "starport-core/lib/StarPortLib.sol";
import {SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {StarPortLib} from "starport-core/lib/StarPortLib.sol";

contract SimpleInterestPricing is BasePricing {
    using FixedPointMathLib for uint256;

    constructor(Starport SP_) Pricing(SP_) {}

    function calculateInterest(
        uint256 delta_t,
        uint256 amount,
        uint256 rate // expressed as SPR seconds per rate
    ) public pure override returns (uint256) {
        return StarPortLib.calculateSimpleInterest(delta_t, amount, rate);
    }

    function isValidRefinance(Starport.Loan memory loan, bytes memory newPricingData, address caller)
        external
        view
        virtual
        override
        returns (
            SpentItem[] memory repayConsideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalConsideration
        )
    {
        Details memory oldDetails = abi.decode(loan.terms.pricingData, (Details));
        Details memory newDetails = abi.decode(newPricingData, (Details));

        //todo: figure out the proper flow for here
        if ((newDetails.rate < oldDetails.rate)) {
            (repayConsideration, carryConsideration) = getPaymentConsideration(loan);
            additionalConsideration = new AdditionalTransfer[](0);
        } else {
            revert InvalidRefinance();
        }
    }
}
