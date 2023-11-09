pragma solidity ^0.8.17;

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Starport} from "starport-core/Starport.sol";

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

enum Actions {
    Nothing,
    Repayment,
    Settlement
}

struct AdditionalTransfer {
    ItemType itemType;
    address token;
    address from;
    address to;
    uint256 identifier;
    uint256 amount;
}

library StarportLib {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    error InvalidSalt();
    error InvalidItemAmount();
    error NativeAssetsNotSupported();
    error InvalidItemTokenNoCode();
    error InvalidItemIdentifier(); //must be zero for ERC20's
    error InvalidItemType();
    error InvalidTransferLength();

    uint256 internal constant _INVALID_SALT = 0x81e69d9b00000000000000000000000000000000000000000000000000000000;

    uint256 internal constant ONE_WORD = 0x20;
    uint256 internal constant CUSTODIAN_WORD_OFFSET = 0x40;

    function getCustodian(bytes calldata data) internal pure returns (address custodian) {
        assembly {
            custodian := calldataload(add(data.offset, CUSTODIAN_WORD_OFFSET))
        }
    }

    function getId(Starport.Loan memory loan) internal pure returns (uint256 loanId) {
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

    function mergeSpentItemsToReceivedItems(
        SpentItem[] memory payment,
        address paymentRecipient,
        SpentItem[] memory carry,
        address carryRecipient
    ) public pure returns (ReceivedItem[] memory consideration) {
        consideration = new ReceivedItem[](payment.length + carry.length);

        uint256 i = 0;
        uint256 j = 0;
        for (; i < payment.length;) {
            if (payment[i].amount > 0) {
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

        if (carry.length > 0) {
            i = 0;
            for (; i < carry.length;) {
                if (carry[i].amount > 0) {
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

    function removeZeroAmountItems(ReceivedItem[] memory consideration)
        internal
        view
        returns (ReceivedItem[] memory newConsideration)
    {
        uint256 j = 0;
        newConsideration = new ReceivedItem[](consideration.length);
        for (uint256 i = 0; i < consideration.length;) {
            if (consideration[i].amount > 0) {
                newConsideration[j] = ReceivedItem({
                    itemType: consideration[i].itemType,
                    identifier: consideration[i].identifier,
                    amount: consideration[i].amount,
                    token: consideration[i].token,
                    recipient: consideration[i].recipient
                });

                unchecked {
                    j++;
                }
            }
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(newConsideration, j)
        }
    }

    function transferAdditionalTransfers(AdditionalTransfer[] memory transfers) internal {
        uint256 i = 0;
        for (i; i < transfers.length;) {
            if (transfers[i].token.code.length == 0) {
                revert InvalidItemTokenNoCode();
            }
            if (transfers[i].itemType == ItemType.ERC20) {
                // erc20 transfer
                if (transfers[i].amount > 0) {
                    SafeTransferLib.safeTransferFrom(
                        transfers[i].token, transfers[i].from, transfers[i].to, transfers[i].amount
                    );
                }
            } else if (transfers[i].itemType == ItemType.ERC721) {
                // erc721 transfer
                ERC721(transfers[i].token).transferFrom(transfers[i].from, transfers[i].to, transfers[i].identifier);
            } else if (transfers[i].itemType == ItemType.ERC1155) {
                // erc1155 transfer
                if (transfers[i].amount > 0) {
                    ERC1155(transfers[i].token).safeTransferFrom(
                        transfers[i].from, transfers[i].to, transfers[i].identifier, transfers[i].amount, new bytes(0)
                    );
                }
            } else {
                revert NativeAssetsNotSupported();
            }
            unchecked {
                ++i;
            }
        }
    }

    function calculateCompoundInterest(
        uint256 delta_t,
        uint256 amount,
        uint256 rate // expressed as SPR seconds per rate
    ) public pure returns (uint256) {
        return amount.mulWad(uint256(int256(rate * delta_t).expWad())) - amount;
    }

    function calculateSimpleInterest(
        uint256 delta_t,
        uint256 amount,
        uint256 rate // expressed as SPR seconds per rate
    ) public pure returns (uint256) {
        return (delta_t * rate).mulWad(amount);
    }

    function _transferItem(
        ItemType itemType,
        address token,
        uint256 identifier,
        uint256 amount,
        address from,
        address to,
        bool safe
    ) internal {
        if (token.code.length == 0) {
            revert InvalidItemTokenNoCode();
        }
        if (itemType == ItemType.ERC20) {
            if (identifier > 0 && safe) {
                revert InvalidItemIdentifier();
            }
            if (amount == 0 && safe) {
                revert InvalidItemAmount();
            }
            SafeTransferLib.safeTransferFrom(token, from, to, amount);
        } else if (itemType == ItemType.ERC721) {
            if (amount != 1 && safe) {
                revert InvalidItemAmount();
            }
            // erc721 transfer
            ERC721(token).transferFrom(from, to, identifier);
        } else if (itemType == ItemType.ERC1155) {
            if (amount == 0 && safe) {
                revert InvalidItemAmount();
            }
            // erc1155 transfer
            ERC1155(token).safeTransferFrom(from, to, identifier, amount, new bytes(0));
        } else {
            revert InvalidItemType();
        }
    }

    function transferSpentItems(SpentItem[] memory transfers, address from, address to, bool safe) internal {
        if (transfers.length > 0) {
            uint256 i = 0;
            for (i; i < transfers.length;) {
                _transferItem(
                    transfers[i].itemType,
                    transfers[i].token,
                    transfers[i].identifier,
                    transfers[i].amount,
                    from,
                    to,
                    safe
                );
                unchecked {
                    ++i;
                }
            }
        } else {
            revert InvalidTransferLength();
        }
    }
}
