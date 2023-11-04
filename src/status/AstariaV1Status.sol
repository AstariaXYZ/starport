pragma solidity ^0.8.17;

import {Starport} from "starport-core/Starport.sol";
import {BaseRecall} from "starport-core/status/BaseRecall.sol";
import {BaseStatus} from "starport-core/status/BaseStatus.sol";
import {StarportLib} from "starport-core/lib/StarportLib.sol";

contract AstariaV1Status is BaseStatus, BaseRecall {
    using {StarportLib.getId} for Starport.Loan;

    constructor(Starport SP_) BaseRecall(SP_) {}

    function isActive(Starport.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.statusData, (Details));
        uint256 tokenId = loan.getId();
        uint64 start = recalls[tokenId].start;
        return !(start > 0 && start + details.recallWindow < block.timestamp);
    }

    function isRecalled(Starport.Loan calldata loan) external view override returns (bool) {
        Details memory details = abi.decode(loan.terms.statusData, (Details));
        uint256 tokenId = loan.getId();
        Recall memory recall = recalls[tokenId];
        return (recall.start + details.recallWindow > block.timestamp) && recall.start != 0;
    }
}
