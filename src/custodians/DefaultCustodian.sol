import {Custodian} from "starport-core/Custodian.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
import {ReceivedItem} from "starport-types/src/lib/ConsiderationStructs.sol";

contract DefaultCustodian is Custodian {
    constructor(LoanManager LM_, address seaport_) Custodian(LM_, seaport_) {}

    function custody(
        ReceivedItem[] calldata consideration,
        bytes32[] calldata orderHashes,
        uint256 contractNonce,
        bytes calldata context
    ) external virtual onlyLoanManager returns (bytes4 selector) {
        selector = Custodian.custody.selector;
    }
}
