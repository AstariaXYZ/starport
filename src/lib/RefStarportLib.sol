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
