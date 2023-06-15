pragma solidity ^0.8.17;

abstract contract Constants {
  struct Signature {
    bytes32 r;
    bytes32 s;
    uint8 v;
  }
}
