const { ethers } = require("hardhat");

const CONTRACT_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3";

async function main() {
  const [admin, bankA, bankB] = await ethers.getSigners();

  const ledger = await ethers.getContractAt("CoreLedger", CONTRACT_ADDRESS);

  await ledger.connect(admin).registerBank(bankA.address, 1000);
  await ledger.connect(admin).registerBank(bankB.address, 500);

  const proofHash =
    "0x1234000000000000000000000000000000000000000000000000000000000000";
  const txId =
    "0x1111000000000000000000000000000000000000000000000000000000000000";

  await ledger.connect(admin).registerValidProof(proofHash);

  await ledger.connect(bankA).transferMoney(
    txId,
    bankB.address,
    100,
    proofHash
  );

  const balanceA = await ledger.getBalance(bankA.address);
  const balanceB = await ledger.getBalance(bankB.address);

  console.log("Bank A:", balanceA.toString());
  console.log("Bank B:", balanceB.toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});