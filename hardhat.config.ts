import "@nomicfoundation/hardhat-foundry";
import "@nomiclabs/hardhat-ethers";
import "@typechain/hardhat";

module.exports = {
  solidity: "0.8.17",
  paths: {
    tests: "./gas-bench",
    src: ["./src", "./lib"]
  }
};

