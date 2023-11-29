// SPDX-License-Identifier: BUSL-1.1
//
//                       ↑↑↑↑                 ↑↑
//                       ↑↑↑↑                ↑↑↑↑↑
//                       ↑↑↑↑              ↑   ↑
//                       ↑↑↑↑            ↑↑↑↑↑
//            ↑          ↑↑↑↑          ↑   ↑
//          ↑↑↑↑↑        ↑↑↑↑        ↑↑↑↑↑
//            ↑↑↑↑↑      ↑↑↑↑      ↑↑↑↑↑                                   ↑↑↑                                                                      ↑↑↑
//              ↑↑↑↑↑    ↑↑↑↑    ↑↑↑↑↑                          ↑↑↑        ↑↑↑         ↑↑↑            ↑↑         ↑↑            ↑↑↑            ↑↑    ↑↑↑
//                ↑↑↑↑↑  ↑↑↑↑  ↑↑↑↑↑                         ↑↑↑↑ ↑↑↑↑   ↑↑↑↑↑↑↑    ↑↑↑↑↑↑↑↑↑     ↑↑ ↑↑↑   ↑↑↑↑↑↑↑↑↑↑↑     ↑↑↑↑↑↑↑↑↑↑    ↑↑↑ ↑↑↑  ↑↑↑↑↑↑↑
//                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑                           ↑↑     ↑↑↑    ↑↑↑     ↑↑↑     ↑↑↑    ↑↑↑      ↑↑↑      ↑↑↑   ↑↑↑      ↑↑↑   ↑↑↑↑       ↑↑↑
//                    ↑↑↑↑↑↑↑↑↑↑                             ↑↑↑↑↑         ↑↑↑            ↑↑↑↑    ↑↑       ↑↑↑       ↑↑   ↑↑↑       ↑↑↑  ↑↑↑        ↑↑↑
//  ↑↑↑↑  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑   ↑↑↑   ↑↑↑             ↑↑↑↑↑↑↑    ↑↑↑     ↑↑↑↑↑↑  ↑↑↑    ↑↑       ↑↑↑       ↑↑↑  ↑↑↑       ↑↑↑  ↑↑↑        ↑↑↑
//  ↑↑↑↑  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑   ↑↑↑   ↑↑↑                  ↑↑    ↑↑↑     ↑↑      ↑↑↑    ↑↑       ↑↑↑      ↑↑↑   ↑↑↑      ↑↑↑   ↑↑↑        ↑↑↑
//                    ↑↑↑↑↑↑↑↑↑↑                             ↑↑↑    ↑↑↑    ↑↑↑     ↑↑↑    ↑↑↑↑    ↑↑       ↑↑↑↑↑  ↑↑↑↑     ↑↑↑↑   ↑↑↑    ↑↑↑        ↑↑↑
//                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑                             ↑↑↑↑↑↑       ↑↑↑↑     ↑↑↑↑↑ ↑↑↑    ↑↑       ↑↑↑ ↑↑↑↑↑↑        ↑↑↑↑↑↑      ↑↑↑          ↑↑↑
//                ↑↑↑↑↑  ↑↑↑↑  ↑↑↑↑↑                                                                       ↑↑↑
//              ↑↑↑↑↑    ↑↑↑↑    ↑↑↑↑                                                                      ↑↑↑     Starport: Lending Kernel
//                ↑      ↑↑↑↑     ↑↑↑↑↑
//                       ↑↑↑↑       ↑↑↑↑↑                                                                          Designed with love by Astaria Labs, Inc
//                       ↑↑↑↑         ↑
//                       ↑↑↑↑
//                       ↑↑↑↑
//                       ↑↑↑↑
//                       ↑↑↑↑

pragma solidity ^0.8.17;

import {Starport} from "../Starport.sol";

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          LIB ENUMS                         */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

enum Actions {
    Nothing,
    Repayment,
    Settlement
}

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                         LIB STRUCTS                        */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error InvalidSalt();
    error InvalidItemAmount();
    error NativeAssetsNotSupported();
    error InvalidItemTokenNoCode();
    error InvalidItemIdentifier(); // Must be zero for ERC20's
    error InvalidItemType();
    error InvalidTransferLength();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    uint256 internal constant _INVALID_SALT = 0x81e69d9b00000000000000000000000000000000000000000000000000000000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PUBLIC FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function calculateSimpleInterest(uint256 delta_t, uint256 amount, uint256 rate, uint256 decimals)
        public
        pure
        returns (uint256)
    {
        rate /= 365 days;
        return ((delta_t * rate) * amount) / 10 ** decimals;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getId(Starport.Loan memory loan) internal pure returns (uint256 loanId) {
        loanId = uint256(keccak256(abi.encode(loan)));
    }

    function validateSalt(
        mapping(address => mapping(bytes32 => bool)) storage usedSalts,
        address borrower,
        bytes32 salt
    ) internal {
        assembly ("memory-safe") {
            mstore(0x0, borrower)
            mstore(0x20, usedSalts.slot)

            // usedSalts[borrower]
            mstore(0x20, keccak256(0x0, 0x40))
            mstore(0x0, salt)

            // usedSalts[borrower][salt]
            let loc := keccak256(0x0, 0x40)

            // if (usedSalts[borrower][salt] == true)
            if iszero(iszero(sload(loc))) {
                // revert InvalidSalt()
                mstore(0x0, _INVALID_SALT)
                revert(0x0, 0x04)
            }

            sstore(loc, 1)
        }
    }

    /**
     * @dev Merges an array of SpentItems into ReceivedItems
     * @param payment The SpentItem[] for payment
     * @param paymentRecipient The recipient address of the payment
     * @param carry The SpentItem[] for carry
     * @param carryRecipient The recipient address of the carry
     * @return consideration An array of ReceivedItems
     */
    function mergeSpentItemsToReceivedItems(
        SpentItem[] memory payment,
        address paymentRecipient,
        SpentItem[] memory carry,
        address carryRecipient
    ) internal pure returns (ReceivedItem[] memory consideration) {
        consideration = new ReceivedItem[](payment.length + carry.length);

        uint256 i = 0;
        uint256 j = 0;
        for (; i < payment.length;) {
            if (payment[i].amount > 0) {
                SpentItem memory paymentItem = payment[i];
                consideration[j] = ReceivedItem({
                    itemType: paymentItem.itemType,
                    identifier: paymentItem.identifier,
                    amount: paymentItem.amount,
                    token: paymentItem.token,
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
                    SpentItem memory carryItem = carry[i];
                    consideration[j] = ReceivedItem({
                        itemType: carryItem.itemType,
                        identifier: carryItem.identifier,
                        amount: carryItem.amount,
                        token: carryItem.token,
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

        assembly ("memory-safe") {
            mstore(consideration, j)
        }
    }

    /**
     * @dev Removes ReceivedItems with zero amounts
     * @param consideration The ReceivedItem[] for payment
     * @return newConsideration An array of ReceivedItems with zero amounts removed
     */
    function removeZeroAmountItems(ReceivedItem[] memory consideration)
        internal
        pure
        returns (ReceivedItem[] memory newConsideration)
    {
        uint256 j = 0;
        newConsideration = new ReceivedItem[](consideration.length);
        for (uint256 i = 0; i < consideration.length;) {
            if (consideration[i].amount > 0) {
                ReceivedItem memory considerationItem = consideration[i];
                newConsideration[j] = ReceivedItem({
                    itemType: considerationItem.itemType,
                    identifier: considerationItem.identifier,
                    amount: considerationItem.amount,
                    token: considerationItem.token,
                    recipient: considerationItem.recipient
                });

                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
        assembly ("memory-safe") {
            mstore(newConsideration, j)
        }
    }

    function transferAdditionalTransfersCalldata(AdditionalTransfer[] calldata transfers) internal {
        uint256 i = 0;
        for (; i < transfers.length;) {
            AdditionalTransfer calldata transfer = transfers[i];
            if (transfer.token.code.length == 0) {
                revert InvalidItemTokenNoCode();
            }
            if (transfer.itemType == ItemType.ERC20) {
                // erc20 transfer
                if (transfer.amount > 0) {
                    SafeTransferLib.safeTransferFrom(transfer.token, transfer.from, transfer.to, transfer.amount);
                }
            } else if (transfer.itemType == ItemType.ERC721) {
                // erc721 transfer
                ERC721(transfer.token).transferFrom(transfer.from, transfer.to, transfer.identifier);
            } else if (transfers[i].itemType == ItemType.ERC1155) {
                // erc1155 transfer
                if (transfer.amount > 0) {
                    ERC1155(transfer.token).safeTransferFrom(
                        transfer.from, transfer.to, transfer.identifier, transfer.amount, new bytes(0)
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

    function transferAdditionalTransfers(AdditionalTransfer[] memory transfers) internal {
        uint256 i = 0;
        for (; i < transfers.length;) {
            AdditionalTransfer memory transfer = transfers[i];
            if (transfer.token.code.length == 0) {
                revert InvalidItemTokenNoCode();
            }
            if (transfer.itemType == ItemType.ERC20) {
                // erc20 transfer
                if (transfer.amount > 0) {
                    SafeTransferLib.safeTransferFrom(transfer.token, transfer.from, transfer.to, transfer.amount);
                }
            } else if (transfer.itemType == ItemType.ERC721) {
                // erc721 transfer
                ERC721(transfer.token).transferFrom(transfer.from, transfer.to, transfer.identifier);
            } else if (transfer.itemType == ItemType.ERC1155) {
                // erc1155 transfer
                if (transfer.amount > 0) {
                    ERC1155(transfer.token).safeTransferFrom(
                        transfer.from, transfer.to, transfer.identifier, transfer.amount, new bytes(0)
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

    function transferSpentItems(SpentItem[] memory transfers, address from, address to, bool safe) internal {
        if (transfers.length > 0) {
            uint256 i = 0;
            for (; i < transfers.length;) {
                SpentItem memory transfer = transfers[i];
                _transferItem(transfer.itemType, transfer.token, transfer.identifier, transfer.amount, from, to, safe);
                unchecked {
                    ++i;
                }
            }
        } else {
            revert InvalidTransferLength();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               PRIVATE INTERNAL FUNCTIONS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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
}
