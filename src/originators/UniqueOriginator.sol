pragma solidity =0.8.17;

import {LoanManager} from "starport-core/LoanManager.sol";

import "starport-core/originators/Originator.sol";

contract UniqueOriginator is Originator {
    constructor(LoanManager LM_, address strategist_, uint256 fee_, address owner)
        Originator(LM_, strategist_, fee_, owner)
    {}

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
}
