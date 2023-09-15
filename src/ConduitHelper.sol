pragma solidity =0.8.17;

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";

import {
  ItemType,
  OfferItem,
  Schema,
  SpentItem,
  ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {
  ContractOffererInterface
} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {
  ConsiderationInterface
} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Originator} from "src/originators/Originator.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {SettlementHandler} from "src/handlers/SettlementHandler.sol";
import {Pricing} from "src/pricing/Pricing.sol";

import {StarPortLib} from "src/lib/StarPortLib.sol";

import "forge-std/console2.sol";
import {
  ConduitTransfer,
  ConduitItemType
} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {
  ConduitControllerInterface
} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {
  ConduitInterface
} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {Custodian} from "src/Custodian.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";
import {CaveatEnforcer} from "src/enforcers/CaveatEnforcer.sol";

abstract contract ConduitHelper {
  error RepayCarryLengthMismatch();

  // TODO: Greg pls help us unfuck this mess
  function _mergeConsiderations(
    ReceivedItem[] memory repayConsideration,
    ReceivedItem[] memory carryConsideration,
    ReceivedItem[] memory additionalConsiderations
  ) internal returns (ReceivedItem[] memory consideration) {
    if (
      carryConsideration.length == 0 && additionalConsiderations.length == 0
    ) {
      return repayConsideration;
    }
    consideration = new ReceivedItem[](
      repayConsideration.length +
        carryConsideration.length +
        additionalConsiderations.length
    );

    uint256 j = 0;
    // if there is a carry to handle, subtract it from the amount owed
    if (carryConsideration.length > 0) {
      if (repayConsideration.length != carryConsideration.length)
        revert RepayCarryLengthMismatch();
      uint256 i = 0;
      for (; i < repayConsideration.length; ) {
        repayConsideration[i].amount -= carryConsideration[i].amount;
        consideration[j] = repayConsideration[i];
        unchecked {
          ++i;
          ++j;
        }
      }
      i = 0;
      for (; i < carryConsideration.length; ) {
        consideration[j] = carryConsideration[i];
        unchecked {
          ++i;
          ++j;
        }
      }
    }
    // else just use the consideration payment only
    else {
      uint256 i = 0;
      for (; i < repayConsideration.length; ) {
        consideration[j] = repayConsideration[i];
        unchecked {
          ++i;
          ++j;
        }
      }
    }

    if (additionalConsiderations.length > 0) {
      uint256 i = 0;
      for (; i < additionalConsiderations.length; ) {
        if (
          consideration[i].recipient == additionalConsiderations[i].recipient &&
          consideration[i].token == additionalConsiderations[i].token
        ) {
          consideration[i].amount += additionalConsiderations[i].amount;
          unchecked {
            ++i;
          }
        } else {
          consideration[j] = additionalConsiderations[i];
          unchecked {
            ++i;
            ++j;
          }
        }
      }
    }
  }

  function _removeZeroAmounts(
    ReceivedItem[] memory consideration
  ) internal view returns (ReceivedItem[] memory newConsideration) {
    uint256 i = 0;
    uint256 validConsiderations = 0;
    for (; i < consideration.length; ) {
      if (consideration[i].amount > 0) ++validConsiderations;
      unchecked {
        ++i;
      }
    }
    i = 0;
    uint256 j = 0;
    newConsideration = new ReceivedItem[](validConsiderations);
    for (; i < consideration.length; ) {
      if (consideration[i].amount > 0) {
        newConsideration[j] = consideration[i];
        unchecked {
          ++j;
        }
      }
      unchecked {
        ++i;
      }
    }
  }

  function _packageTransfers(
    ReceivedItem[] memory refinanceConsideration,
    address refinancer
  ) internal pure returns (ConduitTransfer[] memory transfers) {
    uint256 i = 0;
    uint256 validConsiderations = 0;
    for (; i < refinanceConsideration.length; ) {
      if (refinanceConsideration[i].amount > 0) ++validConsiderations;
      unchecked {
        ++i;
      }
    }
    transfers = new ConduitTransfer[](validConsiderations);
    i = 0;
    uint256 j = 0;
    for (; i < refinanceConsideration.length; ) {
      ConduitItemType itemType;
      ReceivedItem memory debt = refinanceConsideration[i];

      assembly {
        itemType := mload(debt)
        switch itemType
        case 1 {

        }
        case 2 {

        }
        case 3 {

        }
        default {
          revert(0, 0)
        } //TODO: Update with error selector - InvalidContext(ContextErrors.INVALID_LOAN)
      }
      if (refinanceConsideration[i].amount > 0) {
        transfers[j] = ConduitTransfer({
          itemType: itemType,
          from: refinancer,
          token: refinanceConsideration[i].token,
          identifier: refinanceConsideration[i].identifier,
          amount: refinanceConsideration[i].amount,
          to: refinanceConsideration[i].recipient
        });
        unchecked {
          ++j;
        }
      }

      unchecked {
        ++i;
      }
    }
  }
}
