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
pragma solidity ^0.8.17;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {CaveatEnforcer} from "./enforcers/CaveatEnforcer.sol";
import {Starport} from "./Starport.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {ERC1271} from "solady/src/accounts/ERC1271.sol";

//User Flow
//Create account(one time only)
//Transfer collateral to account
//Sign caveat
//Sign intent

// opBatch for Intent
// opBatch[0] = approve collateral to fallback
// opBatch[1] = fallback
// opBatch[2] = saltInvalidation

contract SmartAccount is Ownable {
    error InvalidSigner();

    constructor() Ownable() {
        _initializeOwner(msg.sender);
    }

    struct UserOp {
        address dest;
        uint256 value;
        bytes data;
    }

    struct SignedOps {
        bytes signature;
        UserOp[] opBatch;
    }

    function executeSignedOps(SignedOps calldata signedOps) external payable {
        //validate signature is owner
        _validateSignedOps(signedOps);
        _callBatch(signedOps.opBatch);
    }

    //can be used for misc user interactions
    function executeOwner(UserOp calldata op) external payable onlyOwner {
        _call(op);
    }

    //can be used to execute a failover early and invalidate
    //can be used for misc user interactions
    function executeOwnerBatch(UserOp[] calldata opBatch) external payable onlyOwner {
        _callBatch(opBatch);
    }

    function _callBatch(UserOp[] calldata opBatch) internal {
        for (uint256 i = 0; i < opBatch.length;) {
            _call(opBatch[i]);
            unchecked {
                ++i;
            }
        }
    }

    function _call(UserOp calldata op) internal {
        (bool success, bytes memory result) = op.dest.call{value: op.value}(op.data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _validateSignedOps(SignedOps calldata signedOps) internal view {
        //validate signature is owner
        bytes32 opHash = keccak256(abi.encode(signedOps.opBatch));
        if (!SignatureCheckerLib.isValidSignatureNowCalldata(owner(), opHash, signedOps.signature)) {
            revert InvalidSigner();
        }
    }
    //TODO: add on receive that auto-approves assets to starport?

    //TODO: support 721 signing

    //TODO: add flag to CaveatWithApproval for isEOA and revert accordingly
    function _erc1271Signer() internal view override returns (address) {
        return owner();
    }
}
