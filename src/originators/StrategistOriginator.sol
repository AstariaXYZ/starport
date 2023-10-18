// SPDX-License-Identifier: BUSL-1.1
/**
 *                                                                                                                           ,--,
 *                                                                                                                        ,---.'|
 *      ,----..    ,---,                                                                            ,-.                   |   | :
 *     /   /   \ ,--.' |                  ,--,                                                  ,--/ /|                   :   : |                 ,---,
 *    |   :     :|  |  :                ,--.'|         ,---,          .---.   ,---.    __  ,-.,--. :/ |                   |   ' :               ,---.'|
 *    .   |  ;. /:  :  :                |  |,      ,-+-. /  |        /. ./|  '   ,'\ ,' ,'/ /|:  : ' /  .--.--.           ;   ; '               |   | :     .--.--.
 *    .   ; /--` :  |  |,--.  ,--.--.   `--'_     ,--.'|'   |     .-'-. ' | /   /   |'  | |' ||  '  /  /  /    '          '   | |__   ,--.--.   :   : :    /  /    '
 *    ;   | ;    |  :  '   | /       \  ,' ,'|   |   |  ,"' |    /___/ \: |.   ; ,. :|  |   ,''  |  : |  :  /`./          |   | :.'| /       \  :     |,-.|  :  /`./
 *    |   : |    |  |   /' :.--.  .-. | '  | |   |   | /  | | .-'.. '   ' .'   | |: :'  :  /  |  |   \|  :  ;_            '   :    ;.--.  .-. | |   : '  ||  :  ;_
 *    .   | '___ '  :  | | | \__\/: . . |  | :   |   | |  | |/___/ \:     ''   | .; :|  | '   '  : |. \\  \    `.         |   |  ./  \__\/: . . |   |  / : \  \    `.
 *    '   ; : .'||  |  ' | : ," .--.; | '  : |__ |   | |  |/ .   \  ' .\   |   :    |;  : |   |  | ' \ \`----.   \        ;   : ;    ," .--.; | '   : |: |  `----.   \
 *    '   | '/  :|  :  :_:,'/  /  ,.  | |  | '.'||   | |--'   \   \   ' \ | \   \  / |  , ;   '  : |--'/  /`--'  /        |   ,/    /  /  ,.  | |   | '/ : /  /`--'  /
 *    |   :    / |  | ,'   ;  :   .'   \;  :    ;|   |/        \   \  |--"   `----'   ---'    ;  |,'  '--'.     /         '---'    ;  :   .'   \|   :    |'--'.     /
 *     \   \ .'  `--''     |  ,     .-./|  ,   / '---'          \   \ |                       '--'      `--'---'                   |  ,     .-.//    \  /   `--'---'
 *      `---`               `--`---'     ---`-'                  '---"                                                              `--`---'    `-'----'
 *
 * Chainworks Labs
 */
pragma solidity =0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";

import {ItemType, ReceivedItem, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";

import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {Originator} from "starport-core/originators/Originator.sol";

// Validator abstract contract that lays out the necessary structure and functions for the validator
contract StrategistOriginator is Ownable, Originator {
    event StrategistTransferred(address newStrategist);

    mapping(bytes32 => bool) public usedHashes;

    struct Details {
        address custodian;
        address conduit;
        address issuer;
        uint256 deadline;
        Offer offer;
    }

    struct Offer {
        bytes32 salt; //can be bytes32(0) if so do not invalidate the hash
        LoanManager.Terms terms;
        SpentItem[] collateral;
        SpentItem[] debt;
    }

    event CounterUpdated();

    event HashInvalidated(bytes32 hash);

    modifier onlyLoanManager() {
        if (msg.sender != address(LM)) {
            revert NotLoanManager();
        }
        _;
    }

    error NotLoanManager();
    error NotAuthorized();
    error InvalidDebt();
    error InvalidDebtLength();
    error InvalidDebtAmount();
    error InvalidCustodian();
    error InvalidCollateral();
    error InvalidDeadline();
    error InvalidOffer();
    error InvalidSigner();
    error ConduitTransferError();

    LoanManager public immutable LM;

    // Define the EIP712 domain and typehash constants for generating signatures
    bytes32 constant EIP_DOMAIN = keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant ORIGINATOR_DETAILS_TYPEHASH = keccak256("Origination(uint256 nonce,bytes32 hash)");
    bytes32 constant VERSION = keccak256("0");

    bytes32 internal immutable _DOMAIN_SEPARATOR;

    // Strategist address and fee
    address public strategist;
    uint256 public strategistFee;
    uint256 private _counter;

    constructor(LoanManager LM_, address strategist_, uint256 fee_, address owner) {
        _initializeOwner(owner);
        strategist = strategist_;
        strategistFee = fee_;
        LM = LM_;
        _DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP_DOMAIN,
                VERSION, //version
                block.chainid,
                address(this)
            )
        );
    }

    function setStrategist(address newStrategist) external onlyOwner {
        strategist = newStrategist;
        emit StrategistTransferred(newStrategist);
    }

    function _buildResponse(Request calldata params, Details memory details)
        internal
        virtual
        returns (Response memory response)
    {
        response = Response({terms: details.offer.terms, issuer: details.issuer});
    }

    // Encode the data with the account's nonce for generating a signature
    function encodeWithAccountCounter(bytes32 contextHash) public view virtual returns (bytes memory) {
        bytes32 hash = keccak256(abi.encode(ORIGINATOR_DETAILS_TYPEHASH, _counter, contextHash));

        return abi.encodePacked(bytes1(0x19), bytes1(0x01), _DOMAIN_SEPARATOR, hash);
    }

    function getStrategistData() public view virtual returns (address, uint256) {
        return (strategist, strategistFee);
    }

    // Get the nonce of an account
    function getCounter() public view virtual returns (uint256) {
        return _counter;
    }

    function incrementCounter() external {
        if (msg.sender != strategist || msg.sender != owner()) {
            revert NotAuthorized();
        }
        _counter += uint256(blockhash(block.number - 1) << 0x80);
        emit CounterUpdated();
    }

    // Function to generate the domain separator for signatures
    function domainSeparator() public view virtual returns (bytes32) {
        return _DOMAIN_SEPARATOR;
    }

    function execute(Request calldata params)
        external
        virtual
        override
        onlyLoanManager
        returns (Response memory response)
    {
        Details memory details = abi.decode(params.details, (Details));
        _validateOffer(params, details);
        _execute(params, details);
        response = _buildResponse(params, details);
    }

    function _validateAsk(Request calldata request, Details memory details) internal virtual {
        if (keccak256(abi.encode(request.collateral)) != keccak256(abi.encode(details.offer.collateral))) {
            revert InvalidCollateral();
        }

        //loop through collateral and check if the collateral is the same

        for (uint256 i = 0; i < request.collateral.length;) {
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
                i++;
            }
        }
    }

    function _validateOffer(Request calldata request, Details memory details) internal virtual {
        bytes32 contextHash = keccak256(request.details);
        _validateSignature(keccak256(encodeWithAccountCounter(keccak256(request.details))), request.approval);
        if (request.custodian != details.custodian) {
            revert InvalidCustodian();
        }
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

    function _execute(Request calldata request, Details memory details) internal virtual {
        if (
            ConduitInterface(details.conduit).execute(_packageTransfers(request.debt, request.receiver, details.issuer))
                != ConduitInterface.execute.selector
        ) {
            revert ConduitTransferError();
        }
    }

    function _validateSignature(bytes32 hash, bytes memory signature) internal view virtual {
        if (!SignatureCheckerLib.isValidSignatureNow(strategist, hash, signature)) {
            revert InvalidSigner();
        }
    }
}
