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

import {SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";

abstract contract Originator is Ownable {
    struct Response {
        LoanManager.Terms terms;
        address issuer;
    }

    struct Request {
        address custodian;
        address receiver;
        SpentItem[] collateral;
        SpentItem[] debt;
        bytes details;
        bytes approval;
    }

    event Origination(uint256 indexed loanId, address indexed issuer, bytes nlrDetails);

    function execute(Request calldata params) external virtual returns (Response memory response);

    function _packageTransfers(SpentItem[] memory loan, address borrower, address issuer)
        internal
        pure
        returns (ConduitTransfer[] memory transfers)
    {
        uint256 i = 0;
        transfers = new ConduitTransfer[](loan.length);
        for (; i < loan.length;) {
            ConduitItemType itemType;
            SpentItem memory debt = loan[i];

            assembly {
                itemType := mload(debt)
                switch itemType
                case 1 {}
                case 2 {}
                case 3 {}
                default { revert(0, 0) } //TODO: Update with error selector - InvalidContext(ContextErrors.INVALID_LOAN)
            }
            transfers[i] = ConduitTransfer({
                itemType: itemType,
                from: issuer,
                token: loan[i].token,
                identifier: loan[i].identifier,
                amount: loan[i].amount,
                to: borrower
            });
            unchecked {
                ++i;
            }
        }
    }
}
