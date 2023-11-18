pragma solidity ^0.8.17;

import {ItemType, SpentItem, ReceivedItem, ConsiderationItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import "starport-test/utils/FuzzStructs.sol" as Fuzz;
import "forge-std/Test.sol";
import {Starport} from "starport-core/Starport.sol";

library Cast {
    function toUint(uint8 input) internal pure returns (uint256 ret) {
        assembly ("memory-safe") {
            ret := input
        }
    }

    function toUint(address input) internal pure returns (uint256 ret) {
        assembly ("memory-safe") {
            ret := input
        }
    }

    function toItemType(uint256 input) internal pure returns (ItemType ret) {
        assembly ("memory-safe") {
            ret := input
        }
    }

    function toStorage(ConsiderationItem[] memory a, ConsiderationItem[] storage b) internal {
        assembly ("memory-safe") {
            sstore(b.slot, mload(a))
        }
        for (uint256 i; i < a.length; i++) {
            b[i] = a[i];
        }
    }

    function toStorage(SpentItem[] memory a, SpentItem[] storage b) internal {
        assembly ("memory-safe") {
            sstore(b.slot, mload(a))
        }

        for (uint256 i; i < a.length; i++) {
            b[i] = a[i];
        }
    }

    function toStorage(Starport.Loan memory a, Starport.Loan storage b) internal {
        b.start = a.start;
        b.custodian = a.custodian;
        b.borrower = a.borrower;
        b.issuer = a.issuer;
        b.originator = a.originator;
        b.terms = a.terms;
        toStorage(a.collateral, b.collateral);
        toStorage(a.debt, b.debt);
    }

    function toMemory(SpentItem[] storage a) internal view returns (SpentItem[] memory) {
        SpentItem[] memory b = new SpentItem[](a.length);
        for (uint256 i; i < a.length; i++) {
            b[i] = a[i];
        }
        return b;
    }

    function toMemory(Starport.Loan storage a) internal view returns (Starport.Loan memory) {
        Starport.Loan memory b = Starport.Loan({
            start: a.start,
            custodian: a.custodian,
            borrower: a.borrower,
            issuer: a.issuer,
            originator: a.originator,
            debt: toMemory(a.debt),
            collateral: toMemory(a.collateral),
            terms: a.terms
        });
        return b;
    }
}
