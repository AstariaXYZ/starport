import { expect } from "chai";
import { describe, it } from "mocha";
import { ethers } from "hardhat";
import { UniqueOriginator__factory } from "../typechain-types/factories/src/originators";
import { LoanManager__factory } from "../typechain-types/factories/src";
import { ERC20__factory } from "../typechain-types/factories/lib/solady/src/tokens";

describe("Loan Open Benchmarks", function () {
  it("", async function () {
    // one year in the future
    //    const lm = await ethers.getContractFactoryFromArtifact("LoanManager.sol");
  });
});

async function setUp() {
  const [astaria, strategist, lender, borrower] = await ethers.getSigners();

  const conduitController = await (
    await ethers.getContractFactory("ConduitController")
  ).deploy();
  const consideration = await (
    await ethers.getContractFactory("Consideration")
  ).deploy();
  const debtToken = await (
    await ethers.getContractFactory("TestToken")
  ).deploy();

  const loanManager = await new LoanManager__factory(astaria).deploy(
    consideration.address
  );
  const uniqueOriginator = await new UniqueOriginator__factory(lender).deploy(
    loanManager.address,
    conduitController.address,
    strategist.address,
    0
  );
}
