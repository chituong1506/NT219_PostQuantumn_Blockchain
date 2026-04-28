const { ethers } = require("hardhat");

async function main() {
  const CoreLedger = await ethers.getContractFactory("CoreLedger");
  const contract = await CoreLedger.deploy();

  await contract.deployed();

  console.log("Contract deployed at:", contract.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});