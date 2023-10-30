pragma solidity ^0.8.17;

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {LoanManager} from "starport-core/LoanManager.sol";
import "forge-std/console.sol";

enum Actions {
    Nothing,
    Origination,
    Refinance,
    Repayment,
    Settlement
}

library StarPortLib {
    error InvalidSalt();

    uint256 internal constant _INVALID_SALT = 0x81e69d9b00000000000000000000000000000000000000000000000000000000;

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
            let r := add(s, 0x80) // first recipient offset
            for {} lt(ptr, s) {
                ptr := add(ptr, 0x20)
                c := add(c, 0x80)
                o := add(o, 0xA0)
                r := add(r, 0xA0)
            } {
                mstore(ptr, o) //store offset
                calldatacopy(o, c, 0x80)
                mstore(r, recipient) //set recipient
            }
        }
    }

    function encodeWithRecipient(ReceivedItem[] calldata receivedItems, address recipient)
        internal
        pure
        returns (ReceivedItem[] memory result)
    {
        assembly {
            //set `result` pointer to free memory
            result := mload(0x40)

            let n := receivedItems.length

            //store length of `result`
            mstore(result, n)

            //set `ptr` to start of first struct offset
            let ptr := add(result, 0x20)

            //`s` = offset of first struct
            let s := add(ptr, mul(n, 0x20))

            //expand memory
            mstore(0x40, add(ptr, mul(n, 0xC0)))

            //copy struct data
            calldatacopy(s, receivedItems.offset, mul(n, 0xA0))

            //store struct offsets - first offset starts at end of offsets
            let o := s
            let r := add(s, 0x80) // first recipient offset
            for {} lt(ptr, s) {
                ptr := add(ptr, 0x20)
                o := add(o, 0xA0)
                r := add(r, 0xA0)
            } {
                mstore(ptr, o) //store offset
                mstore(r, recipient) //set recipient
            }
        }
    }

    function validateSalt(
        mapping(address => mapping(bytes32 => bool)) storage usedSalts,
        address borrower,
        bytes32 salt
    ) internal {
        assembly {
            mstore(0x0, borrower)
            mstore(0x20, usedSalts.slot)

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

    function mergeSpentItemsToRecievedItems(SpentItem[] memory payment, address paymentRecipient, SpentItem[] memory carry, address carryRecipient) public pure returns(ReceivedItem[] memory consideration){
        consideration = new ReceivedItem[](payment.length + carry.length);

        uint256 i = 0;
        uint256 j = 0;
        for(;i<payment.length;){
            if(payment[i].amount > 0){
                consideration[j] = ReceivedItem({
                    itemType: payment[i].itemType,
                    identifier: payment[i].identifier,
                    amount: payment[i].amount,
                    token: payment[i].token,
                    recipient: payable(paymentRecipient)
                });

                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        if(carry.length > 0) {
            i = 0;
            for(;i<carry.length;){
                if(carry[i].amount > 0){
                    consideration[j] = ReceivedItem({
                        itemType: carry[i].itemType,
                        identifier: carry[i].identifier,
                        amount: carry[i].amount,
                        token: carry[i].token,
                        recipient: payable(carryRecipient)
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

        assembly {
            mstore(consideration, j)
        }
    } 
}
