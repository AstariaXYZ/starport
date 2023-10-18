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

abstract contract ConduitHelper {
    uint256 internal constant RECEIVED_AMOUNT_OFFSET = 0x60;

    function _mergeAndRemoveZeroAmounts(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsiderations,
        uint256 validCount
    ) internal pure virtual returns (ReceivedItem[] memory consideration) {
        assembly {
            function consumingCopy(arr, ptr) -> out {
                let size := mload(arr)
                let end := add(arr, mul(add(1, size), 0x20))
                for { let i := add(0x20, arr) } lt(i, end) { i := add(i, 0x20) } {
                    let amount := mload(add(mload(i), RECEIVED_AMOUNT_OFFSET))
                    if iszero(amount) { continue }
                    mstore(ptr, mload(i))
                    ptr := add(ptr, 0x20)
                }
                //reset old array length
                mstore(arr, 0)
                out := ptr
            }

            //Set consideration to free memory
            consideration := mload(0x40)
            //Expand memory
            mstore(0x40, add(add(0x20, consideration), mul(validCount, 0x20)))
            mstore(consideration, validCount)
            pop(
                consumingCopy(
                    additionalConsiderations,
                    consumingCopy(carryConsideration, consumingCopy(repayConsideration, add(consideration, 0x20)))
                )
            )
        }
    }

    function _mergeAndRemoveZeroAmounts(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsiderations
    ) internal pure virtual returns (ReceivedItem[] memory consideration) {
        uint256 validCount = 0;
        validCount = _countNonZeroAmounts(repayConsideration, validCount);
        validCount = _countNonZeroAmounts(carryConsideration, validCount);
        validCount = _countNonZeroAmounts(additionalConsiderations, validCount);
        consideration =
            _mergeAndRemoveZeroAmounts(repayConsideration, carryConsideration, additionalConsiderations, validCount);
    }

    function _packageTransfers(ReceivedItem[] memory refinanceConsideration, address refinancer)
        internal
        pure
        virtual
        returns (ConduitTransfer[] memory transfers)
    {
        uint256 validConsiderations = _countNonZeroAmounts(refinanceConsideration, 0);
        transfers = new ConduitTransfer[](validConsiderations);
        uint256 i = 0;
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
        assembly {
            let size := mload(arr)
            let i := add(arr, 0x20)
            let end := add(i, mul(size, 0x20))
            for {} lt(i, end) { i := add(i, 0x20) } {
                let amount := mload(add(mload(i), RECEIVED_AMOUNT_OFFSET))
                if iszero(amount) { continue }
                validCount := add(validCount, 1)
            }
        }
        return validCount;
    }
}
