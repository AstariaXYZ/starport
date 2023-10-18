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

import {ItemType, OfferItem, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";

abstract contract RefConduitHelper {
    error RepayCarryLengthMismatch();

    function _mergeAndRemoveZeroAmounts(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsiderations
    ) internal pure virtual returns (ReceivedItem[] memory consideration) {
        unchecked {
            consideration =
            new ReceivedItem[](repayConsideration.length + carryConsideration.length + additionalConsiderations.length);

            uint256 i = 0;
            uint256 n = repayConsideration.length;
            for (; i < n; i++) {
                consideration[i] = repayConsideration[i];
            }
            uint256 offset = n;
            if (carryConsideration.length > 0) {
                n += carryConsideration.length;
                for (; i < n; ++i) {
                    consideration[i] = carryConsideration[i - offset];
                }
            }
            if (additionalConsiderations.length > 0) {
                offset = n;
                n += additionalConsiderations.length;

                for (; i < n; ++i) {
                    consideration[i] = additionalConsiderations[i - offset];
                }
            }
        }
        assembly {
          mstore(repayConsideration, 0)
          mstore(carryConsideration, 0) 
          mstore(additionalConsiderations, 0)
        }
        consideration = _removeZeroAmounts(consideration);
    }

    function _removeZeroAmounts(ReceivedItem[] memory consideration)
        internal
        pure
        virtual
        returns (ReceivedItem[] memory newConsideration)
    {
        uint256 i = 0;
        uint256 validConsiderations = 0;
        for (; i < consideration.length;) {
            if (consideration[i].amount > 0) ++validConsiderations;
            unchecked {
                ++i;
            }
        }
        i = 0;
        uint256 j = 0;
        newConsideration = new ReceivedItem[](validConsiderations);
        for (; i < consideration.length;) {
            if (consideration[i].amount > 0) {
                newConsideration[j] = consideration[i];
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    function _packageTransfers(ReceivedItem[] memory refinanceConsideration, address refinancer)
        internal
        pure
        returns (ConduitTransfer[] memory transfers)
    {
        uint256 validConsiderations = _countNonZeroAmounts(refinanceConsideration, 0);
        transfers = new ConduitTransfer[](validConsiderations);
        uint256 i = 0;
        i = 0;
        uint256 j = 0;
        for (; i < refinanceConsideration.length;) {
            ConduitItemType itemType;
            ReceivedItem memory debt = refinanceConsideration[i];

            assembly {
                itemType := mload(debt)
                switch itemType
                case 1 {}
                case 2 {}
                case 3 {}
                default { revert(0, 0) } //TODO: Update with error selector - InvalidContext(ContextErrors.INVALID_LOAN)
            }
            if (refinanceConsideration[i].amount > 0) {
                transfers[j] = ConduitTransfer({
                    itemType: itemType,
                    from: refinancer,
                    token: refinanceConsideration[i].token,
                    identifier: refinanceConsideration[i].identifier,
                    amount: refinanceConsideration[i].amount,
                    to: refinanceConsideration[i].recipient
                });
                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function _countNonZeroAmounts(ReceivedItem[] memory arr, uint256 validCount)
        internal
        pure
        virtual
        returns (uint256)
    {
        for (uint256 i; i < arr.length;) {
            unchecked {
                if (arr[i].amount > 0) ++validCount;
                ++i;
            }
        }
        return validCount;
    }
}
