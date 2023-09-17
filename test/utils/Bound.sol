pragma solidity =0.8.17;

import {ItemType, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Cast} from "test/utils/Cast.sol";
import "test/utils/FuzzStructs.sol" as Fuzz;
import "forge-std/Test.sol";

abstract contract Bound is StdUtils {
  using Cast for *;

  function _boundItemType(uint8 itemType) internal pure returns (ItemType) {
    return _bound(itemType, uint8(ItemType.NATIVE), uint8(ItemType.ERC1155_WITH_CRITERIA)).toItemType();
  }

  function _boundSpentItem(Fuzz.SpentItem memory input) internal pure returns (SpentItem memory ret) {
    ret = SpentItem({
      itemType: _boundItemType(input.itemType),
      token: input.token,
      identifier: input.identifier,
      amount: input.amount
    });
  }

  function _boundSpentItems(Fuzz.SpentItem[] memory input) internal pure returns (SpentItem[] memory ret) {
    ret = new SpentItem[](input.length);
    for (uint256 i = 0; i < input.length; i++) {
      ret[i] = _boundSpentItem(input[i]);
    }
  }

  function _boundReceivedItem(Fuzz.ReceivedItem memory input) internal pure returns (ReceivedItem memory ret) {
    ret = ReceivedItem({
      itemType: _boundItemType(input.itemType),
      token: input.token,
      identifier: input.identifier,
      amount: input.amount,
      recipient: input.recipient
    });
  }

  function _boundReceivedItems(Fuzz.ReceivedItem[] memory input) internal pure returns (ReceivedItem[] memory ret) {
    ret = new ReceivedItem[](input.length);
    for (uint256 i = 0; i < input.length; i++) {
      ret[i] = _boundReceivedItem(input[i]);
    }
  }
}
