pragma solidity ^0.8.17;

import {
    OfferItem,
    SpentItem,
    ConsiderationItem,
    AdvancedOrder,
    OrderParameters,
    CriteriaResolver,
    ItemType,
    Fulfillment
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";

import {Seaport} from "seaport/contracts/Seaport.sol";
import {LoanManager} from "./LoanManager.sol";
import {CaveatEnforcer} from "./enforcers/CaveatEnforcer.sol";
import "forge-std/console.sol";

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

interface IWETH9 {
    function withdraw(uint256) external;
}

interface ERC20 {
    function transfer(address, uint256) external returns (bool);
}

// fulfiller

contract BNPLHelper is IFlashLoanRecipient {
    address private constant vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IWETH9 private immutable WETH;
    bytes32 private activeUserDataHash;

    constructor(address WETH_) {
        WETH = IWETH9(WETH_);
    }

    struct Execution {
        address lm;
        address seaport;
        address borrower;
        CaveatEnforcer.CaveatWithApproval borrowerCaveat;
        CaveatEnforcer.CaveatWithApproval lenderCaveat;
        LoanManager.Loan loan;
        AdvancedOrder[] orders;
        CriteriaResolver[] resolvers;
        Fulfillment[] fulfillments;
    }

    error SenderNotSelf();
    error DoNotSendETH();
    error InvalidUserDataProvided();

    function makeFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        //        uint256[] calldata userProvidedAmounts,
        bytes calldata userData
    ) external {
        //        assembly {
        //            // Compute the hash of userData
        //            let dataHash := keccak256(userData.offset, calldatasize())
        //
        //            // Store the hash in the activeUserDataHash state variable
        //            tstore(activeUserDataHash.slot, dataHash)
        //        }
        activeUserDataHash = keccak256(userData);

        IVault(vault).flashLoan(this, tokens, amounts, userData);
    }

    function receiveFlashLoan(
        address[] calldata tokens, // are all erc20s
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) external override {
        require(msg.sender == vault);

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

        ConduitTransfer[] memory transfers = new ConduitTransfer[](tokens.length);
        for (uint256 i = 0; i < tokens.length;) {
            transfers[i] = ConduitTransfer({
                itemType: ConduitItemType.ERC20,
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
        LoanManager(execution.lm).originate(transfers, execution.borrowerCaveat, execution.lenderCaveat, execution.loan);
    }

    receive() external payable {
        if (msg.sender != address(WETH)) {
            revert DoNotSendETH();
        }
    }
}
