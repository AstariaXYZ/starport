pragma solidity =0.8.17;

import {CaveatEnforcer} from "./CaveatEnforcer.sol";
import {LoanManager} from "src/LoanManager.sol";

import {ItemType, SpentItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

contract CollateralEnforcer is CaveatEnforcer {
    struct Details {
        SpentItem[] collateral;
        bool isAny; // TODO delete?
    }

    function enforceCaveat(bytes calldata terms, LoanManager.Loan memory loan)
        public
        view
        override
        returns (bool valid)
    {
        Details memory details = abi.decode(terms, (Details));
        //TODO: figure out or/and comparison simple impl

        return (keccak256(abi.encode(loan.collateral)) == keccak256(abi.encode(details.collateral)));
    }
}
