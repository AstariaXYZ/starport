pragma solidity ^0.8.17;

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {LoanManager} from "starport-core/LoanManager.sol";

library StarPortLib {
    error InvalidSalt();

    uint256 internal constant _INVALID_SALT = 0x81e69d9b00000000000000000000000000000000000000000000000000000000;
    uint256 internal constant _RECEIVED_ITEM_RECIPIENT_OFFSET = 0x80;
    uint256 internal constant _RECEIVED_ITEM_SIZE = 0xA0;

    function getId(LoanManager.Loan memory loan) internal pure returns (uint256 loanId) {
        loanId = uint256(keccak256(abi.encode(loan)));
    }

    function toReceivedItems(SpentItem[] calldata spentItems, address recipient)
        internal
        pure
        returns (ReceivedItem[] memory result)
    {
        assembly {
            //set `result` pointer to free memory
            result := mload(0x40)

            let n := spentItems.length

            //store length of `result`
            mstore(result, n)

            //set `ptr` to start of first struct offset
            let ptr := add(result, 0x20)

            //`s` = offset of first struct
            let s := add(ptr, mul(n, 0x20))

            //expand memory
            mstore(0x40, add(ptr, mul(n, 0xC0)))

            //store struct offsets - first offset starts at end of offsets
            let o := s
            let c := spentItems.offset
            let r := add(s, _RECEIVED_ITEM_RECIPIENT_OFFSET) // first recipient offset
            for {} lt(ptr, s) {
                ptr := add(ptr, 0x20)
                c := add(c, _RECEIVED_ITEM_RECIPIENT_OFFSET)
                o := add(o, _RECEIVED_ITEM_SIZE)
                r := add(r, _RECEIVED_ITEM_SIZE)
            } {
                mstore(ptr, o) //store offset
                calldatacopy(o, c, 0x80)
                mstore(r, recipient) //set recipient
            }
        }
    }

    function validateSaltRef(
        mapping(address => mapping(bytes32 => bool)) storage usedSalts,
        address borrower,
        bytes32 salt
    ) internal {
        if (usedSalts[borrower][salt]) {
            revert InvalidSalt();
        }
        usedSalts[borrower][salt] = true;
    }

    function validateSalt(
        mapping(address => mapping(bytes32 => bool)) storage usedSalts,
        address borrower,
        bytes32 salt
    ) internal {
        assembly {
            mstore(0x20, usedSalts.slot)
            mstore(0x0, borrower)

            //usedSalts[borrower]
            mstore(0x20, keccak256(0x0, 0x40))
            mstore(0x0, salt)

            //usedSalts[borrower][salt]
            let loc := keccak256(0x0, 0x40)

            //if (usedSalts[borrower][salt] == true)
            if iszero(iszero(sload(loc))) {
                //revert InvalidSalt()
                mstore(0x0, _INVALID_SALT)
                revert(0x0, 0x04)
            }

            sstore(loc, 1)
        }
    }

    uint256 internal constant RECEIVED_AMOUNT_OFFSET = 0x60;

    function _mergeAndRemoveZeroAmounts(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsiderations,
        uint256 validCount
    ) internal pure returns (ReceivedItem[] memory consideration) {
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

    function _countNonZeroAmounts(ReceivedItem[] memory arr, uint256 validCount) internal pure returns (uint256) {
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

    function _mergeAndRemoveZeroAmounts(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration,
        ReceivedItem[] memory additionalConsiderations
    ) internal pure returns (ReceivedItem[] memory consideration) {
        uint256 validCount = 0;
        validCount = _countNonZeroAmounts(repayConsideration, validCount);
        validCount = _countNonZeroAmounts(carryConsideration, validCount);
        validCount = _countNonZeroAmounts(additionalConsiderations, validCount);
        consideration =
            _mergeAndRemoveZeroAmounts(repayConsideration, carryConsideration, additionalConsiderations, validCount);
    }

    function _mergeAndRemoveZeroAmounts(
        ReceivedItem[] memory repayConsideration,
        ReceivedItem[] memory carryConsideration
    ) internal pure returns (ReceivedItem[] memory consideration) {
        uint256 validCount = 0;
        validCount = _countNonZeroAmounts(repayConsideration, validCount);
        validCount = _countNonZeroAmounts(carryConsideration, validCount);
        consideration =
            _mergeAndRemoveZeroAmounts(repayConsideration, carryConsideration, new ReceivedItem[](0), validCount);
    }
}
