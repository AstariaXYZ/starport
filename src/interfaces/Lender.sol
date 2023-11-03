pragma solidity ^0.8.17;

import "starport-core/Starport.sol";

abstract contract Lender {
    function onSettle(Starport.Loan calldata loan) external virtual returns (bytes4 selector) {
        selector = Lender.onSettle.selector;
    }
}
