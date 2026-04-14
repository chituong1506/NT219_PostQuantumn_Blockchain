const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');

// Contract address
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || '0x42699A7612A82f1d9C36148af9C77354759b210b';

// RPC endpoint
const host = process.env.RPC_ENDPOINT || "http://127.0.0.1:21001";

// Load contract ABI
const contractJsonPath = path.resolve(__dirname, '../../', 'contracts', 'InterbankTransfer.json');
const contractJson = JSON.parse(fs.readFileSync(contractJsonPath));
const contractAbi = contractJson.abi;

// Conversion rates
const WEI_TO_ETH = BigInt(10 ** 18);
const ETH_TO_VND_RATE = 1000000; // 1 ETH = 1,000,000 VND

function weiToVnd(wei) {
  const ethValue = Number(wei) / Number(WEI_TO_ETH);
  return Math.floor(ethValue * ETH_TO_VND_RATE);
}

// Danh sách users cần check
const USERS = [
  { address: '0x6423CfdF2B3E2E94613266631f22EA0e8788e34e', name: 'Vietcombank User 1' },
  { address: '0x1444808f0AfF7ec6008A416450Dd4e14069d436D', name: 'Vietcombank User 2' },
  { address: '0x469Bb95e092005ba56a786fAAAE10BA38285E1c8', name: 'VietinBank User 1' },
  { address: '0x2e27a0742fbbF51245b606DF46165e7eFa412b7C', name: 'VietinBank User 2' },
  { address: '0x12B7D41e4Cf1f380a838067127a32E30B42b3e73', name: 'BIDV User 1' },
  { address: '0x21f0e22d5974Ecd5EDC1efDF1135A39Ff1474E9D', name: 'BIDV User 2' },
];

async function checkBalance(userAddress, userName) {
  try {
    const provider = new ethers.JsonRpcProvider(host);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, contractAbi, provider);
    
    // Check contract balance
    const balanceWei = await contract.getBalance(userAddress);
    const balanceETH = ethers.formatEther(balanceWei);
    const balanceVND = weiToVnd(balanceWei);
    
    // Check native balance
    const nativeBalanceWei = await provider.getBalance(userAddress);
    const nativeBalanceETH = ethers.formatEther(nativeBalanceWei);
    
    // Check if authorized
    const isAuthorized = await contract.authorizedBanks(userAddress);
    
    return {
      address: userAddress,
      name: userName,
      contractBalanceWei: balanceWei.toString(),
      contractBalanceETH: balanceETH,
      contractBalanceVND: balanceVND,
      nativeBalanceETH: nativeBalanceETH,
      isAuthorized: isAuthorized,
    };
  } catch (error) {
    return {
      address: userAddress,
      name: userName,
      error: error.message,
    };
  }
}

async function main() {
  const userAddress = process.argv[2];
  
  console.log('🔍 Checking balances...\n');
  console.log(`Contract address: ${CONTRACT_ADDRESS}`);
  console.log(`RPC endpoint: ${host}\n`);
  console.log('='.repeat(80));
  
  if (userAddress) {
    // Check single user
    const user = USERS.find(u => u.address.toLowerCase() === userAddress.toLowerCase());
    if (!user) {
      console.log(`⚠️  User not found, checking address anyway: ${userAddress}`);
      const result = await checkBalance(userAddress, 'Custom Address');
      printResult(result);
    } else {
      const result = await checkBalance(user.address, user.name);
      printResult(result);
    }
  } else {
    // Check all users
    for (const user of USERS) {
      const result = await checkBalance(user.address, user.name);
      printResult(result);
      console.log('');
    }
  }
  
  console.log('='.repeat(80));
}

function printResult(result) {
  console.log(`\n👤 ${result.name || 'Unknown'}`);
  console.log(`   Address: ${result.address}`);
  
  if (result.error) {
    console.log(`   ❌ Error: ${result.error}`);
    return;
  }
  
  console.log(`   ✅ Authorized: ${result.isAuthorized ? 'Yes' : 'No'}`);
  console.log(`   💰 Contract Balance:`);
  console.log(`      - Wei: ${result.contractBalanceWei}`);
  console.log(`      - ETH: ${result.contractBalanceETH}`);
  console.log(`      - VND: ${result.contractBalanceVND.toLocaleString('vi-VN')} ₫`);
  console.log(`   💵 Native Balance: ${result.nativeBalanceETH} ETH`);
  
  if (BigInt(result.contractBalanceWei) === 0n) {
    console.log(`   ⚠️  WARNING: Contract balance is 0! User needs to deposit.`);
  }
}

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error('❌ Error:', error);
      process.exit(1);
    });
}

module.exports = { checkBalance };

