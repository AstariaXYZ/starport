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

import {Starport} from "starport-core/Starport.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";

import {Seaport} from "seaport/contracts/Seaport.sol";
import {
    AdvancedOrder,
    ConsiderationItem,
    CriteriaResolver,
    Fulfillment,
    ItemType,
    OfferItem,
    OrderParameters,
    SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                        INTERFACES                          */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

interface IVault {
    function flashLoan(
        IFlashLoanRecipient recipient,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes memory userData
    ) external;
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes memory userData
    ) external;
}

interface ERC20 {
    function transfer(address, uint256) external returns (bool);
}

contract BNPLHelper is IFlashLoanRecipient {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error DoNotSendETH();
    error InvalidUserDataProvided();
    error SenderNotVault();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    address private constant vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    bytes32 private activeUserDataHash;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Execution {
        address lm;
        address seaport;
        address borrower;
        CaveatEnforcer.SignedCaveats borrowerCaveat;
        CaveatEnforcer.SignedCaveats lenderCaveat;
        Starport.Loan loan;
        AdvancedOrder[] orders;
        CriteriaResolver[] resolvers;
        Fulfillment[] fulfillments;
    }

    function makeFlashLoan(address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData) external {
        activeUserDataHash = keccak256(userData);

        IVault(vault).flashLoan(this, tokens, amounts, userData);
    }

    function receiveFlashLoan(
        address[] calldata tokens, // Are all ERC-20s
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external override {
        if (msg.sender != vault) {
            revert SenderNotVault();
        }

        if (activeUserDataHash != keccak256(userData)) {
            revert InvalidUserDataProvided();
        }
        delete activeUserDataHash;

        Execution memory execution = abi.decode(userData, (Execution));

        // Approve seaport
        for (uint256 i = 0; i < tokens.length;) {
            ERC20(tokens[i]).transfer(execution.borrower, amounts[i]);
            unchecked {
                ++i;
            }
        }
        Seaport(payable(execution.seaport)).matchAdvancedOrders(
            execution.orders, execution.resolvers, execution.fulfillments, execution.borrower
        );

        AdditionalTransfer[] memory transfers = new AdditionalTransfer[](tokens.length);
        for (uint256 i = 0; i < tokens.length;) {
            transfers[i] = AdditionalTransfer({
                itemType: ItemType.ERC20,
                identifier: 0,
                token: tokens[i],
                from: execution.borrower,
                to: vault,
                amount: amounts[i] + feeAmounts[i]
            });
            unchecked {
                ++i;
            }
        }
        Starport(execution.lm).originate(transfers, execution.borrowerCaveat, execution.lenderCaveat, execution.loan);
    }
}
