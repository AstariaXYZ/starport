import { expect } from "chai";
import { describe, it } from "mocha";
import { ethers } from "hardhat";
import { UniqueValidator__factory } from "../typechain-types/factories/src/validators";
import { LoanManager__factory } from "../typechain-types/factories/src";
import { MockERC20__factory } from "../typechain-types/factories/lib/solmate/src/tokens";
//import { UniqueValidator__factory } from "../typechain-types/factories/src/";

describe("Loan Open Benchmarks", function() {
  it("", async function() {

    // one year in the future
    //    const lm = await ethers.getContractFactoryFromArtifact("LoanManager.sol");


  });
});

async function setUp() {
  const [astaria, strategist, lender, borrower] = await ethers.getSigners();

  const conduitController = await (await ethers.getContractFactory("ConduitController")).deploy();
  const consideration = await (await ethers.getContractFactory("Consideration")).deploy();
  const debtToken = await (await ethers.getContractFactory("TestToken")).deploy();

  const loanManager = await new LoanManager__factory(astaria).deploy(consideration.address);
  const uniqueValidator = await new UniqueValidator__factory(lender).deploy(
    loanManager.address,
    conduitController.address,
    strategist.address,
    0
  );


  // conduitKeyOne = bytes32(uint256(uint160(address(strategist))) << 96);

  // vm.startPrank(lender);
  // debtToken.approve(address(UV.conduit()), 100000);
  // debtToken.mint(address(lender), 1000);

  // vm.stopPrank();
}//






