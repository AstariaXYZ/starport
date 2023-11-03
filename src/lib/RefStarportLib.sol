pragma solidity ^0.8.17;

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {Starport} from "starport-core/Starport.sol";
import "forge-std/console.sol";

enum Actions {
    Nothing,
    Origination,
    Refinance,
    Repayment,
    Settlement
}

library RefStarportLib {
    error InvalidSalt();

    uint256 internal constant ONE_WORD = 0x20;
    uint256 internal constant CUSTODIAN_WORD_OFFSET = 0x40;

    function getAction(bytes calldata data) internal pure returns (Actions action) {
        assembly {
            action := calldataload(data.offset)
        }
    }

    function getCustodian(bytes calldata data) internal pure returns (address custodian) {
        assembly {
            custodian := calldataload(add(data.offset, CUSTODIAN_WORD_OFFSET))
        }
    }

    function toReceivedItems(SpentItem[] calldata spentItems, address recipient)
        internal
        pure
        returns (ReceivedItem[] memory consideration)
    {
        consideration = new ReceivedItem[](spentItems.length);
        for (uint256 i = 0; i < spentItems.length;) {
            consideration[i] = ReceivedItem({
                itemType: spentItems[i].itemType,
                token: spentItems[i].token,
                identifier: spentItems[i].identifier,
                amount: spentItems[i].amount,
                recipient: payable(recipient)
            });
            unchecked {
                ++i;
            }
        }
    }

    function validateSalt(
        mapping(address => mapping(bytes32 => bool)) storage usedSalts,
        address borrower,
        bytes32 salt
    ) internal {
        if (usedSalts[borrower][salt]) {
            revert InvalidSalt();
        }
        usedSalts[borrower][salt] = true;
    }
}
