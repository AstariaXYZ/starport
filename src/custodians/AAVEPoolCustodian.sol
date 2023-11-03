//pragma solidity ^0.8.17;;
//
//import {ERC20} from "solady/src/tokens/ERC20.sol";
//import "../Custodian.sol";
//
//interface IPool {
//    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
//
//    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
//}
//
//contract AAVEPoolCustodian is Custodian {
//    IPool public pool;
//
//    constructor(Starport SP_, address seaport_, address pool_) Custodian(SP_, seaport_) {
//        pool = IPool(pool_);
//    }
//
//    //gets full seaport context
//    function custody(
//        ReceivedItem[] calldata consideration,
//        bytes32[] calldata orderHashes,
//        uint256 contractNonce,
//        bytes calldata context
//    ) external override returns (bytes4 selector) {
//        _enter(consideration[0].token, consideration[0].amount);
//        selector = AAVEPoolCustodian.custody.selector;
//    }
//
//    function _beforeApprovalsSetHook(address fulfiller, SpentItem[] calldata maximumSpent, bytes calldata context)
//        internal
//        virtual
//        override
//    {
//        _exit(maximumSpent[0].token, maximumSpent[0].amount);
//    }
//
//    function _enter(address token, uint256 amount) internal {
//        ERC20(token).approve(address(pool), amount);
//        pool.supply(token, amount, address(this), 0);
//    }
//
//    function _exit(address token, uint256 amount) internal {
//        pool.withdraw(token, amount, address(this));
//    }
//}
