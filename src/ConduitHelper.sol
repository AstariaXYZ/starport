pragma solidity =0.8.17;


import {ItemType, OfferItem, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";

abstract contract ConduitHelper {
    error RepayCarryLengthMismatch();

    function _mergeConsiderations(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsiderations
    ) internal pure returns (ReceivedItem[] memory consideration) {
        if (carryConsideration.length == 0 && additionalConsiderations.length == 0) {
            return repayConsideration;
        }
        consideration = new ReceivedItem[](repayConsideration.length +
        carryConsideration.length +
        additionalConsiderations.length);

        uint256 j = 0;
        // if there is a carry to handle, subtract it from the amount owed
        if (carryConsideration.length > 0) {
            if (repayConsideration.length != carryConsideration.length) {
                revert RepayCarryLengthMismatch();
            }
            uint256 i = 0;
            for (; i < repayConsideration.length;) {
                repayConsideration[i].amount -= carryConsideration[i].amount;
                consideration[j] = repayConsideration[i];
                unchecked {
                    ++i;
                    ++j;
                }
            }
            i = 0;
            for (; i < carryConsideration.length;) {
                consideration[j] = carryConsideration[i];
                unchecked {
                    ++i;
                    ++j;
                }
            }
        }
        // else just use the consideration payment only
        else {
            for (; j < repayConsideration.length;) {
                consideration[j] = repayConsideration[j];
                unchecked {
                    ++j;
                }
            }
        }

        if (additionalConsiderations.length > 0) {
            uint256 i = 0;
            for (; i < additionalConsiderations.length;) {
                consideration[j] = additionalConsiderations[i];
                unchecked {
                    ++i;
                    ++j;
                }
            }
        }
    }

    function _removeZeroAmounts(ReceivedItem[] memory consideration)
        internal
        view
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
        uint256 i = 0;
        uint256 validConsiderations = 0;
        for (; i < refinanceConsideration.length;) {
            if (refinanceConsideration[i].amount > 0) ++validConsiderations;
            unchecked {
                ++i;
            }
        }
        transfers = new ConduitTransfer[](validConsiderations);
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
}
