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
import {CaveatEnforcer} from "../enforcers/CaveatEnforcer.sol";
import {Originator} from "../originators/Originator.sol";
import {AdditionalTransfer, StarportLib} from "../lib/StarportLib.sol";

import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {TokenReceiverInterface} from "../interfaces/TokenReceiverInterface.sol";

// Validator abstract contract that lays out the necessary structure and functions for the validator
contract StrategistOriginator is Ownable, Originator, TokenReceiverInterface {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error AdditionalTransferError();
    error InvalidCollateral();
    error InvalidDeadline();
    error InvalidDebt();
    error InvalidDebtAmount();
    error InvalidDebtLength();
    error InvalidOffer();
    error InvalidSigner();
    error NotAuthorized();
    error NotStarport();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event CounterUpdated(uint256);
    event HashInvalidated(bytes32 hash);
    event StrategistTransferred(address newStrategist);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    Starport public immutable SP;

    // Define the EIP712 domain and typehash constants for generating signatures
    bytes32 public constant EIP_DOMAIN =
        keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant ORIGINATOR_DETAILS_TYPEHASH = keccak256("Origination(uint256 nonce,bytes32 hash)");
    bytes32 public constant VERSION = keccak256("0");
    bytes32 internal immutable _DOMAIN_SEPARATOR;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    mapping(bytes32 => bool) public usedHashes;

    // Strategist address
    address public strategist;
    uint256 private _counter;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Details {
        address custodian;
        address issuer;
        uint256 deadline;
        Offer offer;
    }

    struct Offer {
        bytes32 salt; // If bytes32(0) do not invalidate the hash
        Starport.Terms terms;
        SpentItem[] collateral;
        SpentItem[] debt;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(Starport SP_, address strategist_, address owner) {
        _initializeOwner(owner);
        strategist = strategist_;
        emit StrategistTransferred(strategist_);
        SP = SP_;
        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP_DOMAIN,
                VERSION, //version
                block.chainid,
                address(this)
            )
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Sets the strategist address
     * @param newStrategist The new strategist address
     */
    function setStrategist(address newStrategist) external onlyOwner {
        strategist = newStrategist;
        emit StrategistTransferred(newStrategist);
    }

    /**
     * @dev increments the Counter to invalidate any open offers
     */
    function incrementCounter() external {
        if (msg.sender != strategist && msg.sender != owner()) {
            revert NotAuthorized();
        }
        uint256 counter;
        unchecked {
            counter = _counter += 1 + uint256(blockhash(block.number - 1) >> 0x80);
        }
        emit CounterUpdated(counter);
    }

    /**
     * @dev Accepts a request with signed data that is decoded by the originator
     * communicates with Starport to originate a loan
     * @param params The request for the origination
     */
    function originate(Request calldata params) external virtual override {
        Details memory details = abi.decode(params.details, (Details));
        _validateOffer(params, details);

        Starport.Loan memory loan = Starport.Loan({
            start: uint256(0), // Set in Starport
            originator: address(0), // Set in Starport
            custodian: details.custodian,
            issuer: details.issuer,
            borrower: params.borrower,
            collateral: params.collateral,
            debt: params.debt,
            terms: details.offer.terms
        });

        CaveatEnforcer.SignedCaveats memory le;
        SP.originate(new AdditionalTransfer[](0), params.borrowerCaveat, le, loan);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PUBLIC FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Returns data that is encodePacked for signing
     * @param contextHash The hash of the data being signed
     */
    function encodeWithAccountCounter(bytes32 contextHash) public view virtual returns (bytes memory) {
        bytes32 hash = keccak256(abi.encode(ORIGINATOR_DETAILS_TYPEHASH, _counter, contextHash));

        return abi.encodePacked(bytes1(0x19), bytes1(0x01), _DOMAIN_SEPARATOR, hash);
    }

    /**
     * @dev Returns the nonce of the contract
     * @return _counter
     */
    function getCounter() public view virtual returns (uint256) {
        return _counter;
    }

    /**
     * @dev Returns the domain separator
     * @return _DOMAIN_SEPARATOR
     */
    function domainSeparator() public view virtual returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _validateAsk(Request calldata request, Details memory details) internal virtual {
        if (keccak256(abi.encode(request.collateral)) != keccak256(abi.encode(details.offer.collateral))) {
            revert InvalidCollateral();
        }

        // Loop through collateral and check if the collateral is the same
        uint256 i = 0;
        for (; i < request.debt.length;) {
            if (
                request.debt[i].itemType != details.offer.debt[i].itemType
                    || request.debt[i].token != details.offer.debt[i].token
                    || request.debt[i].identifier != details.offer.debt[i].identifier
            ) {
                revert InvalidDebt();
            }

            if (
                request.debt[i].amount > details.offer.debt[i].amount || request.debt[i].amount == 0
                    || details.offer.debt[i].amount == 0
            ) {
                revert InvalidDebtAmount();
            }
            unchecked {
                ++i;
            }
        }
    }

    function _validateOffer(Request calldata request, Details memory details) internal virtual {
        bytes32 contextHash = keccak256(request.details);
        _validateSignature(keccak256(encodeWithAccountCounter(keccak256(request.details))), request.approval);
        if (request.debt.length != details.offer.debt.length) {
            revert InvalidDebtLength();
        }
        _validateAsk(request, details);
        if (details.offer.salt != bytes32(0)) {
            if (!usedHashes[contextHash]) {
                usedHashes[contextHash] = true;
                emit HashInvalidated(contextHash);
            } else {
                revert InvalidOffer();
            }
        }
        if (block.timestamp > details.deadline) {
            revert InvalidDeadline();
        }
    }

    function _validateSignature(bytes32 hash, bytes memory signature) internal view virtual {
        if (!SignatureCheckerLib.isValidSignatureNow(strategist, hash, signature)) {
            revert InvalidSigner();
        }
    }

    function withdraw(SpentItem[] memory transfers, address recipient) external onlyOwner {
        StarportLib.transferSpentItemsSelf(transfers, address(this), recipient);
    }

    // PUBLIC FUNCTIONS
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
        pure
        virtual
        override
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        virtual
        override
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        virtual
        override
        returns (bytes4)
    {
        return TokenReceiverInterface.onERC1155BatchReceived.selector;
    }
}
