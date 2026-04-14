const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');
const https = require('https');

// Contract address (đã deploy)
// Có thể set qua environment variable: CONTRACT_ADDRESS
// Hoặc sẽ được tự động set khi chạy deploy_and_init.js
// Hoặc đọc từ file InterbankTransfer.address.txt
function getContractAddress() {
    if (process.env.CONTRACT_ADDRESS) {
        return process.env.CONTRACT_ADDRESS;
    }
    
    // Try to read from file
    const addressPath = path.resolve(__dirname, '../../', 'contracts', 'InterbankTransfer.address.txt');
    if (fs.existsSync(addressPath)) {
        const address = fs.readFileSync(addressPath, 'utf8').trim();
        // Validate address is not a placeholder
        if (address && address !== '0x...' && address.length === 42) {
            return address;
        }
    }
    
    // Fallback to old address (for backward compatibility)
    return '0x42699A7612A82f1d9C36148af9C77354759b210b';
}

// RPC endpoint
const host = process.env.RPC_ENDPOINT || "http://127.0.0.1:21001";

// Deployer private key (owner của contract)
const ownerPrivateKey = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

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

// Số dư ban đầu: 100 triệu VND = 100 ETH (theo tỷ lệ 1 ETH = 1,000 VND)
// 100,000,000 VND = 100 ETH = 100 * 10^18 wei
const INITIAL_ETH_AMOUNT = ethers.parseEther('100'); // 100 ETH (tương đương 100 triệu VND)

// Load contract ABI
const contractJsonPath = path.resolve(__dirname, '../../', 'contracts', 'InterbankTransfer.json');
const contractJson = JSON.parse(fs.readFileSync(contractJsonPath));
const contractAbi = contractJson.abi;

async function initializeContract() {
    try {
        console.log("Connecting to blockchain at:", host);
        
        // Setup provider with TLS support for HTTPS (same as deploy script)
        let fetchRequest = undefined;
        if (host.startsWith('https://')) {
            const CA_CERT_PATH = process.env.CA_CERT_PATH || path.resolve(__dirname, '../../../config/tls/ca/certs/sbv-root-ca.crt');
            const ALLOW_INSECURE_TLS = process.env.ALLOW_INSECURE_TLS === 'true' || process.env.NODE_TLS_REJECT_UNAUTHORIZED === '0';
            
            const httpsAgent = new https.Agent({
                rejectUnauthorized: !ALLOW_INSECURE_TLS,
                ca: fs.existsSync(CA_CERT_PATH) ? fs.readFileSync(CA_CERT_PATH) : undefined
            });
            
            if (fs.existsSync(CA_CERT_PATH)) {
                console.log(`🔒 Using TLS with CA certificate: ${CA_CERT_PATH}`);
            } else if (ALLOW_INSECURE_TLS) {
                console.log(`⚠️  TLS enabled but CA cert not found. Using insecure mode (not recommended)`);
            }
            
            fetchRequest = (url, options) => {
                return fetch(url, {
                    ...options,
                    agent: httpsAgent
                });
            };
        }
        
        // Create provider with ENS disabled for private networks
        const provider = new ethers.JsonRpcProvider(host, undefined, { 
            fetchRequest,
            ensAddress: null  // Disable ENS resolution for private networks
        });
        
        // Kiểm tra kết nối
        const network = await provider.getNetwork();
        console.log(`✅ Connected to network: Chain ID ${network.chainId}`);
        
        // Get contract address at runtime (to pick up env var set by deploy_and_init.js)
        const rawAddress = getContractAddress();
        
        // Validate address before normalizing
        if (!rawAddress || rawAddress === '0x...' || rawAddress.length !== 42) {
            throw new Error(`Invalid contract address: "${rawAddress}". Please ensure CONTRACT_ADDRESS is set or InterbankTransfer.address.txt contains a valid address.`);
        }
        
        // Normalize contract address to ensure proper format (prevents ENS resolution)
        const contractAddress = ethers.getAddress(rawAddress);
        console.log(`📋 Using Contract Address: ${contractAddress}`);
        
        const ownerWallet = new ethers.Wallet(ownerPrivateKey, provider);
        console.log("Owner address:", ownerWallet.address);
        
        // Kiểm tra owner balance
        const ownerBalance = await provider.getBalance(ownerWallet.address);
        console.log("Owner balance:", ethers.formatEther(ownerBalance), "ETH");
        
        if (ownerBalance < INITIAL_ETH_AMOUNT * BigInt(USERS.length)) {
            console.warn(`⚠️ Cảnh báo: Owner balance có thể không đủ để deposit cho ${USERS.length} users`);
            console.warn(`   Cần: ${ethers.formatEther(INITIAL_ETH_AMOUNT * BigInt(USERS.length))} ETH`);
        }
        
        // Get contract instance (use normalized address to prevent ENS resolution)
        const contract = new ethers.Contract(contractAddress, contractAbi, ownerWallet);
        
        // Verify contract is accessible
        const contractOwner = await contract.owner();
        console.log("Contract owner:", contractOwner);
        
        if (contractOwner.toLowerCase() !== ownerWallet.address.toLowerCase()) {
            throw new Error(`Owner mismatch! Contract owner: ${contractOwner}, Wallet: ${ownerWallet.address}`);
        }
        
        // Check if PKI is enabled
        let pkiEnabled = false;
        try {
            pkiEnabled = await contract.pkiEnabled();
            console.log(`PKI Enabled: ${pkiEnabled}`);
            if (pkiEnabled) {
                console.log("⚠️  PKI is enabled. Users need to be registered in PKI first.");
                console.log("   If this is a fresh deploy, PKI should be disabled.");
                console.log("   You can disable PKI temporarily with: togglePKI(false)");
            }
        } catch (error) {
            // Contract might not have pkiEnabled() function (old version)
            console.log("ℹ️  PKI status check skipped (contract may not have PKI integration)");
        }
        
        console.log("\n📋 Bước 1: Authorize bank addresses...");
        // Lấy danh sách bank addresses duy nhất
        const bankAddresses = [...new Set(USERS.map(u => {
            // Lấy bank address từ user address (giả sử bank address là user address)
            // Hoặc bạn có thể có mapping riêng
            return u.address; // Tạm thời dùng user address làm bank address
        }))];
        
        // Authorize các bank addresses
        for (const user of USERS) {
            try {
                // Check if already authorized
                const isAuthorized = await contract.authorizedBanks(user.address);
                if (!isAuthorized) {
                    console.log(`  Authorizing ${user.address} (${user.bankCode})...`);
                    const tx = await contract.addAuthorizedBank(user.address, user.bankCode, {
                        gasLimit: 15000000, // Max gas limit
                        gasPrice: 0,
                    });
                    await tx.wait(1);
                    console.log(`  ✅ Authorized ${user.address}`);
                } else {
                    console.log(`  ⏭️  ${user.address} already authorized`);
                }
            } catch (error) {
                console.error(`  ❌ Error authorizing ${user.address}:`, error.message);
            }
        }
        
        console.log("\n📋 Bước 2: Deposit initial balance for all users...");
        let successCount = 0;
        let failCount = 0;
        
        for (const user of USERS) {
            try {
                // Check current balance
                const currentBalance = await contract.getBalance(user.address);
                
                if (currentBalance > 0n) {
                    console.log(`  ⏭️  ${user.address} already has balance: ${ethers.formatEther(currentBalance)} ETH`);
                    continue;
                }
                
                console.log(`  Depositing ${ethers.formatEther(INITIAL_ETH_AMOUNT)} ETH to ${user.address} (${user.bankCode})...`);
                
                // Deposit với số tiền kèm theo (payable function)
                const tx = await contract.deposit(user.address, user.bankCode, {
                    value: INITIAL_ETH_AMOUNT,
                    gasLimit: 15000000, // Max gas limit
                    gasPrice: 0,
                });
                
                console.log(`    Transaction hash: ${tx.hash}`);
                const receipt = await tx.wait(1);
                
                // Verify balance after deposit
                const newBalance = await contract.getBalance(user.address);
                console.log(`    ✅ Deposit successful! New balance: ${ethers.formatEther(newBalance)} ETH`);
                successCount++;
                
            } catch (error) {
                console.error(`    ❌ Error depositing to ${user.address}:`, error.message);
                failCount++;
            }
        }
        
        console.log("\n✅ Initialization completed!");
        console.log(`   Success: ${successCount}/${USERS.length}`);
        console.log(`   Failed: ${failCount}/${USERS.length}`);
        
        // Verify all balances
        console.log("\n📊 Final balances:");
        for (const user of USERS) {
            const balance = await contract.getBalance(user.address);
            console.log(`   ${user.address.slice(0, 10)}... (${user.bankCode}): ${ethers.formatEther(balance)} ETH`);
        }
        
    } catch (error) {
        console.error("❌ Initialization failed:", error);
        throw error;
    }
}

async function main() {
    await initializeContract()
        .then(() => {
            console.log("\n✅ Initialization script completed!");
            process.exit(0);
        })
        .catch((error) => {
            console.error("\n❌ Initialization script failed:", error.message);
            process.exit(1);
        });
}

if (require.main === module) {
    main();
}

module.exports = { initializeContract };

