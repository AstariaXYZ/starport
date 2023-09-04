import "./StarPortTest.sol";

contract TestStorage {
  uint256[] loans;

  function setupLoans(uint256 num) public {
    for (uint256 i = 0; i < num; i++) {
      loans.push(i);
    }
  }

  function hashLoans() public view returns (bytes32) {
    return keccak256(abi.encode(loans));
  }
}

contract TestLoanManager is StarPortTest {
  function testSupportsInterface() public {
    assertTrue(
      LM.supportsInterface(type(ContractOffererInterface).interfaceId)
    );
    assertTrue(LM.supportsInterface(type(ERC721).interfaceId));
  }

  function testStorage() public {
    TestStorage ts = new TestStorage();
    ts.setupLoans(100000);
    bytes32 hash = ts.hashLoans();
    console.logBytes32(hash);
  }
}
