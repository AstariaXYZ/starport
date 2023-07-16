import "./StarPortTest.sol";

contract TestLoanManager is StarPortTest {
  function testSupportsInterface() public {
    assertTrue(
      LM.supportsInterface(type(ContractOffererInterface).interfaceId)
    );
    assertTrue(LM.supportsInterface(type(ERC721).interfaceId));
  }
}
