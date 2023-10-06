pragma solidity =0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";

import "starport-core/originators/Originator.sol";

contract UniqueOriginator is Originator {
    constructor(LoanManager LM_, address strategist_, uint256 fee_) Originator(LM_, strategist_, fee_, msg.sender) {}
}
