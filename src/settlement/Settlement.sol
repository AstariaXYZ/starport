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
import {Validation} from "starport-core/lib/Validation.sol";

import {ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

abstract contract Settlement is Validation {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    Starport public immutable SP;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(Starport SP_) {
        SP = SP_;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /*
    * @dev Called by the Custodian after a loan has been settled
    * @param loan The loan that has been settled
    * @param fulfiller The address of the fulfiller
    */
    function postSettlement(Starport.Loan calldata loan, address fulfiller) external virtual returns (bytes4);

    /*
    * @dev Called by the Starport/Custodian after a loan has been repaid
    * @param loan The loan that has been settled
    * @param fulfiller The address of the fulfiller
    */
    function postRepayment(Starport.Loan calldata loan, address fulfiller) external virtual returns (bytes4);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PUBLIC FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /*
    * @dev helper to get the consideration for a loan
    * @param loan The loan in question
    * @return consideration The settlement consideration for the loan
    * @return address The address of the authorized party (if any)
    */
    function getSettlementConsideration(Starport.Loan calldata loan)
        public
        view
        virtual
        returns (ReceivedItem[] memory consideration, address authorized);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     FUNCTION OVERRIDES                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /*
    * @dev standard erc1155 received hook
    */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}
