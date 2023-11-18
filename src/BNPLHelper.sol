// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2023 Astaria Labs

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
    address private constant vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    bytes32 private activeUserDataHash;

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

    error DoNotSendETH();
    error InvalidUserDataProvided();
    error SenderNotVault();

    function makeFlashLoan(address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData) external {
        activeUserDataHash = keccak256(userData);

        IVault(vault).flashLoan(this, tokens, amounts, userData);
    }

    function receiveFlashLoan(
        address[] calldata tokens, // are all erc20s
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
        //approve seaport
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
                token: tokens[0],
                from: execution.borrower,
                to: vault,
                amount: amounts[0] + feeAmounts[0]
            });
            unchecked {
                ++i;
            }
        }
        Starport(execution.lm).originate(transfers, execution.borrowerCaveat, execution.lenderCaveat, execution.loan);
    }
}
