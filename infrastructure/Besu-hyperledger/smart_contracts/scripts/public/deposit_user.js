const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');

// Contract address
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS || '0x42699A7612A82f1d9C36148af9C77354759b210b';

// RPC endpoint
const host = process.env.RPC_ENDPOINT || "http://127.0.0.1:21001";

// Owner private key (có quyền deposit)
const ownerPrivateKey = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// Số dư ban đầu: 100 ETH = 100 triệu VND
const INITIAL_ETH_AMOUNT = ethers.parseEther('100'); // 100 ETH

// Load contract ABI
const contractJsonPath = path.resolve(__dirname, '../../', 'contracts', 'InterbankTransfer.json');
const contractJson = JSON.parse(fs.readFileSync(contractJsonPath));
const contractAbi = contractJson.abi;

/**
 * Deposit số dư cho một user bất kỳ
 */
async function depositForUser(userAddress, bankCode = 'EXTERNAL') {
    try {
        const provider = new ethers.JsonRpcProvider(host);
        const ownerWallet = new ethers.Wallet(ownerPrivateKey, provider);
        
        // Check owner balance
        const ownerBalance = await provider.getBalance(ownerWallet.address);
        if (ownerBalance < INITIAL_ETH_AMOUNT) {
            throw new Error(`Owner balance (${ethers.formatEther(ownerBalance)} ETH) không đủ để deposit (cần ${ethers.formatEther(INITIAL_ETH_AMOUNT)} ETH)`);
        }
        
        const contract = new ethers.Contract(CONTRACT_ADDRESS, contractAbi, ownerWallet);
        
        // Check if user already has balance (skip check if called from depositAllUsers)
        const currentBalance = await contract.getBalance(userAddress);
        if (currentBalance > 0n) {
            // Only skip if called directly (not from depositAllUsers)
            if (process.argv.length > 2) {
                console.log(`⚠️  User đã có balance: ${ethers.formatEther(currentBalance)} ETH`);
                return currentBalance;
            }
        }
        
        // Check if user is authorized (if not, authorize first)
        const isAuthorized = await contract.authorizedBanks(userAddress);
        if (!isAuthorized) {
            console.log(`  Authorizing user...`);
            const authTx = await contract.addAuthorizedBank(userAddress, bankCode, {
                gasLimit: 15000000, // Max gas limit
                gasPrice: 0,
            });
            await authTx.wait(1);
            console.log(`  ✅ User đã được authorize`);
        }
        
        // Deposit
        console.log(`  Depositing ${ethers.formatEther(INITIAL_ETH_AMOUNT)} ETH...`);
        const tx = await contract.deposit(userAddress, bankCode, {
            value: INITIAL_ETH_AMOUNT,
            gasLimit: 15000000, // Max gas limit
            gasPrice: 0,
        });
        
        console.log(`  Transaction hash: ${tx.hash}`);
        const receipt = await tx.wait(1);
        
        // Verify
        const newBalance = await contract.getBalance(userAddress);
        console.log(`  ✅ Deposit successful! New balance: ${ethers.formatEther(newBalance)} ETH`);
        
        return newBalance;
        
    } catch (error) {
        console.error(`  ❌ Error:`, error.message);
        throw error;
    }
}

// Danh sách users cần deposit (addresses đúng từ private keys trong banks.ts)
const USERS = [
    // Vietcombank (addresses đã được cập nhật để match với private keys)
    { address: '0x6423CfdF2B3E2E94613266631f22EA0e8788e34e', bankCode: 'VCB' },
    { address: '0x1444808f0AfF7ec6008A416450Dd4e14069d436D', bankCode: 'VCB' },
    // VietinBank
    { address: '0x469Bb95e092005ba56a786fAAAE10BA38285E1c8', bankCode: 'VTB' },
    { address: '0x2e27a0742fbbF51245b606DF46165e7eFa412b7C', bankCode: 'VTB' },
    // BIDV
    { address: '0x12B7D41e4Cf1f380a838067127a32E30B42b3e73', bankCode: 'BIDV' },
    { address: '0x21f0e22d5974Ecd5EDC1efDF1135A39Ff1474E9D', bankCode: 'BIDV' },
];

/**
 * Deposit cho tất cả users trong danh sách
 */
async function depositAllUsers() {
    console.log("🚀 Bắt đầu deposit số dư cho tất cả users...\n");
    console.log(`Tổng số users: ${USERS.length}\n`);
    
    let successCount = 0;
    let skipCount = 0;
    let failCount = 0;
    
    for (let i = 0; i < USERS.length; i++) {
        const user = USERS[i];
        console.log(`[${i + 1}/${USERS.length}] Processing: ${user.address} (${user.bankCode})`);
        
        try {
            // Check current balance
            const provider = new ethers.JsonRpcProvider(host);
            const contract = new ethers.Contract(CONTRACT_ADDRESS, contractAbi, provider);
            const currentBalance = await contract.getBalance(user.address);
            
            if (currentBalance > 0n) {
                console.log(`  ⏭️  Đã có balance: ${ethers.formatEther(currentBalance)} ETH - Bỏ qua`);
                skipCount++;
                continue;
            }
            
            // Deposit
            await depositForUser(user.address, user.bankCode);
            successCount++;
            console.log('');
            
        } catch (error) {
            console.error(`  ❌ Error: ${error.message}`);
            failCount++;
        }
    }
    
    console.log("\n" + "=".repeat(60));
    console.log("📊 Kết quả:");
    console.log(`   ✅ Thành công: ${successCount}`);
    console.log(`   ⏭️  Đã có balance: ${skipCount}`);
    console.log(`   ❌ Thất bại: ${failCount}`);
    console.log("=".repeat(60));
}

// Get user address from command line (optional)
const userAddress = process.argv[2];
const bankCode = process.argv[3] || 'EXTERNAL';

async function main() {
    if (userAddress) {
        // Deposit cho một user cụ thể
        await depositForUser(userAddress, bankCode)
            .then(() => {
                console.log('\n✅ Done!');
                process.exit(0);
            })
            .catch((error) => {
                console.error('\n❌ Failed:', error.message);
                process.exit(1);
            });
    } else {
        // Tự động deposit cho tất cả users
        await depositAllUsers()
            .then(() => {
                console.log('\n✅ Hoàn tất deposit cho tất cả users!');
                process.exit(0);
            })
            .catch((error) => {
                console.error('\n❌ Failed:', error.message);
                process.exit(1);
            });
    }
}

if (require.main === module) {
    main();
}

module.exports = { depositForUser };

