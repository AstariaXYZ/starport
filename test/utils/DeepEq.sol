import {
  ItemType,
  SpentItem,
  ReceivedItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Cast} from "test/utils/Cast.sol";
import "test/utils/FuzzStructs.sol" as Fuzz;
import "forge-std/Test.sol";

abstract contract DeepEq {
  function _deepEq(
    ReceivedItem[] memory a,
    ReceivedItem[] memory b
  ) internal pure {
    assert(a.length == b.length);
    for (uint256 i = 0; i < a.length; i++) {
      assert(a[i].itemType == b[i].itemType);
      assert(a[i].token == b[i].token);
      assert(a[i].identifier == b[i].identifier);
      assert(a[i].amount == b[i].amount);
      assert(a[i].recipient == b[i].recipient);
    }
  }

  function _deepEq(SpentItem[] memory a, SpentItem[] memory b) internal pure {
    assert(a.length == b.length);
    for (uint256 i = 0; i < a.length; i++) {
      assert(a[i].itemType == b[i].itemType);
      assert(a[i].token == b[i].token);
      assert(a[i].identifier == b[i].identifier);
      assert(a[i].amount == b[i].amount);
    }
  }
}
