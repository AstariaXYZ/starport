pragma solidity ^0.8.17;

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {Starport} from "starport-core/Starport.sol";

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

    function validateSalt(
        mapping(address => mapping(bytes32 => bool)) storage usedSalts,
        address borrower,
        bytes32 salt
    ) internal {
        if (salt != bytes32(0)) {
            if (usedSalts[borrower][salt]) {
                revert InvalidSalt();
            }
            usedSalts[borrower][salt] = true;
        }
    }
}
