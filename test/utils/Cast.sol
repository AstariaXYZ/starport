pragma solidity =0.8.17;

import {ItemType, SpentItem, ReceivedItem, ConsiderationItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import "test/utils/FuzzStructs.sol" as Fuzz;
import "forge-std/Test.sol";
import {LoanManager} from "src/LoanManager.sol";

library Cast {
    function toUint(uint8 input) internal pure returns (uint256 ret) {
        assembly {
            ret := input
        }
    }

    function toUint(address input) internal pure returns (uint256 ret) {
        assembly {
            ret := input
        }
    }

    function toItemType(uint256 input) internal pure returns (ItemType ret) {
        assembly {
            ret := input
        }
    }

    function toStorage(ConsiderationItem memory a, ConsiderationItem storage b) internal {
        b.itemType = a.itemType;
        b.startAmount = a.startAmount;
        b.endAmount = a.endAmount;
        b.identifierOrCriteria = a.identifierOrCriteria;
        b.token = a.token;
        b.recipient = a.recipient;
    }

    function toStorage(ConsiderationItem[] memory a, ConsiderationItem[] storage b) internal {
        assembly {
            sstore(b.slot, mload(a))
        }
        for (uint256 i; i < a.length; i++) {
            toStorage(a[i], b[i]);
        }
    }

    function toStorage(SpentItem memory a, SpentItem storage b) internal {
        b.itemType = a.itemType;
        b.token = a.token;
        b.amount = a.amount;
        b.identifier = a.identifier;
    }

    function toStorage(SpentItem[] memory a, SpentItem[] storage b) internal {
        assembly {
            sstore(b.slot, mload(a))
        }

        for (uint256 i; i < a.length; i++) {
            toStorage(a[i], b[i]);
        }
    }

    function toStorage(LoanManager.Loan memory a, LoanManager.Loan storage b) internal {
        b.start = a.start;
        b.custodian = a.custodian;
        b.borrower = a.borrower;
        b.issuer = a.issuer;
        b.originator = a.originator;
        b.terms = a.terms;
        toStorage(a.collateral, b.collateral);
        toStorage(a.debt, b.debt);
    }

    function toMemory(SpentItem storage a, SpentItem memory b) internal view {
        b.itemType = a.itemType;
        b.token = a.token;
        b.amount = a.amount;
        b.identifier = a.identifier;
    }

    function toMemory(SpentItem[] storage a) internal view returns (SpentItem[] memory) {
        SpentItem[] memory b = new SpentItem[](a.length);
        for (uint256 i; i < a.length; i++) {
            toMemory(a[i], b[i]);
        }
        return b;
    }

    function toMemory(LoanManager.Loan storage a) internal view returns (LoanManager.Loan memory) {
        LoanManager.Loan memory b = LoanManager.Loan({
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
