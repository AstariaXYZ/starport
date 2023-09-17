pragma solidity =0.8.17;

struct ReceivedItem {
  uint8 itemType;
  address token;
  uint256 identifier;
  uint256 amount;
  address payable recipient;
}

struct SpentItem {
  uint8 itemType;
  address token;
  uint256 identifier;
  uint256 amount;
}
