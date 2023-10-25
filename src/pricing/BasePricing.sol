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
import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

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
        returns (SpentItem[] memory repayConsideration, SpentItem[] memory carryConsideration)
    {
        // repayConsideration = _generateRepayConsideration(loan);
        // carryConsideration = _generateRepayCarryConsideration(loan);
        
        Details memory details = abi.decode(loan.terms.pricingData, (Details));
        if(details.carryRate > 0) carryConsideration = new SpentItem[](loan.debt.length);
        else carryConsideration = new SpentItem[](0);
        repayConsideration = new SpentItem[](loan.debt.length);

        uint256 i=0;
        for(;i<loan.debt.length;){
            uint256 interest = getInterest(loan, details, loan.start, block.timestamp, i);
            
            if(details.carryRate > 0){
                carryConsideration[i] = SpentItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: interest.mulWad(details.carryRate),
                    token: loan.debt[i].token
                });
                repayConsideration[i] = SpentItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: loan.debt[i].amount + interest - carryConsideration[i].amount,
                    token: loan.debt[i].token
                });
            }
            else {
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

    function getOwed(LoanManager.Loan memory loan) public view returns (uint256[] memory) {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));
        return _getOwed(loan, details, loan.start, block.timestamp);
    }

    function _getOwedCarry(LoanManager.Loan memory loan, Details memory details, uint256 timestamp)
        internal
        view
        returns (uint256[] memory carryOwed)
    {
        carryOwed = new uint256[](loan.debt.length);
        uint256 i = 0;

        for (; i < loan.debt.length;) {
            uint256 carry = getInterest(loan, details, loan.start, timestamp, i).mulWad(details.carryRate);
            carryOwed[i] = carry;
            unchecked {
                ++i;
            }
        }
    }

    function _getOwed(LoanManager.Loan memory loan, Details memory details, uint256 start, uint256 end)
        internal
        view
        returns (uint256[] memory updatedDebt)
    {
        updatedDebt = new uint256[](loan.debt.length);
        for (uint256 i = 0; i < loan.debt.length; i++) {
            updatedDebt[i] = loan.debt[i].amount + getInterest(loan, details, start, end, i);
        }
    }

    function getInterest(
        LoanManager.Loan memory loan,
        Details memory details,
        uint256 start,
        uint256 end,
        uint256 index
    ) public view returns (uint256) {
        uint256 delta_t = end - start;
        return calculateInterest(delta_t, details.rate, loan.debt[index].amount);
    }

    function calculateInterest(
        uint256 delta_t,
        uint256 amount,
        uint256 rate // expressed as SPR seconds per rate
    ) public pure virtual returns (uint256);

    function _generateRepayConsideration(LoanManager.Loan memory loan)
        internal
        view
        returns (SpentItem[] memory consideration)
    {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));

        consideration = new SpentItem[](loan.debt.length);
        uint256[] memory owing = _getOwed(loan, details, loan.start, block.timestamp);

        uint256 i = 0;
        for (; i < consideration.length;) {
            consideration[i] = SpentItem({
                itemType: loan.debt[i].itemType,
                identifier: loan.debt[i].identifier,
                amount: owing[i],
                token: loan.debt[i].token
            });
            unchecked {
                ++i;
            }
        }
    }

    function _generateRepayCarryConsideration(LoanManager.Loan memory loan)
        internal
        view
        returns (SpentItem[] memory consideration)
    {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));

        if (details.carryRate == 0) return new SpentItem[](0);
        uint256[] memory owing = _getOwedCarry(loan, details, block.timestamp);
        consideration = new SpentItem[](owing.length);
        uint256 i = 0;
        for (; i < consideration.length;) {
            consideration[i] = SpentItem({
                itemType: loan.debt[i].itemType,
                identifier: loan.debt[i].identifier,
                amount: owing[i],
                token: loan.debt[i].token
            });
            unchecked {
                ++i;
            }
        }
    }
}
