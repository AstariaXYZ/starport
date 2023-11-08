import {Ownable} from "solady/src/auth/Ownable.sol";

abstract contract PausableNonReentrant is Ownable {
    uint256 private constant _UNLOCKED = 0x1;
    uint256 private constant _LOCKED = 0x2;
    uint256 private constant _PAUSED = 0x3;

    uint256 private _state = _UNLOCKED;

    event Paused();
    event Unpaused();

    error IsPaused();
    error IsLocked();
    error NotPaused();

    /*
    * @dev modifier to ensure that the contract is not paused or locked
    */
    modifier pausableNonReentrant() {
        assembly {
            //If locked or paused, handle revert cases
            if gt(sload(_state.slot), _UNLOCKED) {
                if gt(sload(_state.slot), _LOCKED) {
                    //Revert IsPaused
                    mstore(0, 0x1309a563)
                    revert(0x1c, 0x04)
                }
                //Revert IsLocked
                mstore(0, 0xcaa30f55)
                revert(0x1c, 0x04)
            }
            sstore(_state.slot, _LOCKED)
        }
        _;
        assembly {
            sstore(_state.slot, _UNLOCKED)
        }
    }

    /*
    * @dev Pause the contract if not paused or locked
    */
    function pause() external onlyOwner {
        assembly {
            //If locked, prevent owner from overriding state
            if eq(sload(_state.slot), _LOCKED) {
                //Revert IsLocked
                mstore(0, 0xcaa30f55)
                revert(0x1c, 0x04)
            }
            sstore(_state.slot, _PAUSED)
        }
        emit Paused();
    }

    /*
    * @dev unpause the contract if not paused or locked
    */
    function unpause() external onlyOwner {
        assembly {
            //If not paused, prevent owner from overriding state
            if lt(sload(_state.slot), _PAUSED) {
                //Revert NotPaused
                mstore(0, 0x6cd60201)
                revert(0x1c, 0x04)
            }
            sstore(_state.slot, _UNLOCKED)
        }
        emit Unpaused();
    }

    /*
    * @dev helper to determine if the contract is paused
    * @return bool True if the contract is paused, false otherwise
    */
    function paused() external view returns (bool) {
        return _state == _PAUSED;
    }
}
