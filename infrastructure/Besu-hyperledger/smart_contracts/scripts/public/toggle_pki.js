// Toggle PKI enabled/disabled on InterbankTransfer contract
// Usage: node toggle_pki.js [true|false]
// Default: false (disable PKI)

const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');

// Contract address
function getContractAddress() {
    if (process.env.CONTRACT_ADDRESS) {
        return process.env.CONTRACT_ADDRESS;
    }
    
    const addressPath = path.resolve(__dirname, '../../', 'contracts', 'InterbankTransfer.address.txt');
    if (fs.existsSync(addressPath)) {
        const address = fs.readFileSync(addressPath, 'utf8').trim();
        if (address && address !== '0x...' && address.length === 42) {
            return address;
        }
    }
    
    throw new Error('Contract address not found. Please set CONTRACT_ADDRESS or ensure InterbankTransfer.address.txt exists.');
}

// RPC endpoint
const host = process.env.RPC_ENDPOINT || "https://localhost:21001";

// Owner private key
const ownerPrivateKey = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// Load contract ABI
const contractJsonPath = path.resolve(__dirname, '../../', 'contracts', 'InterbankTransfer.json');
const contractJson = JSON.parse(fs.readFileSync(contractJsonPath));
const contractAbi = contractJson.abi;

async function togglePKI() {
    try {
        // Parse argument
        const enablePKI = process.argv[2] === 'true' || process.argv[2] === '1';
        
        console.log(`🔐 Toggling PKI: ${enablePKI ? 'ENABLE' : 'DISABLE'}`);
        console.log(`   RPC: ${host}`);
        
        // Disable SSL verification for localhost
        process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
        
        const provider = new ethers.JsonRpcProvider(host);
        const ownerWallet = new ethers.Wallet(ownerPrivateKey, provider);
        const contractAddress = getContractAddress();
        const contract = new ethers.Contract(contractAddress, contractAbi, ownerWallet);
        
        console.log(`   Contract: ${contractAddress}`);
        console.log(`   Owner: ${ownerWallet.address}`);
        
        // Check current PKI status
        const currentPKIStatus = await contract.pkiEnabled();
        console.log(`   Current PKI status: ${currentPKIStatus}`);
        
        if (currentPKIStatus === enablePKI) {
            console.log(`   ✅ PKI already ${enablePKI ? 'enabled' : 'disabled'}, no change needed`);
            return;
        }
        
        // Toggle PKI
        console.log(`\n📝 Toggling PKI...`);
        
        // Get current nonce from blockchain and wait if too high
        let currentNonce = await provider.getTransactionCount(ownerWallet.address, 'pending');
        console.log(`   Current nonce: ${currentNonce}`);
        
        // If nonce is too high, wait for transactions to be mined
        // Besu has a nonce gap limit, so we need to wait for pending transactions
        if (currentNonce > 50) {
            console.log(`   ⚠️  Nonce is high (${currentNonce}), waiting for pending transactions to be mined...`);
            console.log(`   This may take a while if many transactions are pending...`);
            const startBlock = await provider.getBlockNumber();
            const startNonce = currentNonce;
            // Wait up to 5 minutes for transactions to be mined
            for (let i = 0; i < 300; i++) {
                await new Promise(resolve => setTimeout(resolve, 1000));
                const newNonce = await provider.getTransactionCount(ownerWallet.address, 'pending');
                const currentBlock = await provider.getBlockNumber();
                // Nonce should decrease as transactions are mined, or blocks should advance
                if (newNonce < startNonce - 10 || currentBlock > startBlock + 10) {
                    currentNonce = newNonce;
                    console.log(`   ✅ Nonce updated: ${currentNonce} (after ${i+1}s, ${currentBlock - startBlock} blocks)`);
                    break;
                }
                if (i % 30 === 29) {
                    console.log(`   ... still waiting (${i+1}s, nonce: ${newNonce}, blocks: ${currentBlock - startBlock})...`);
                }
            }
            // Final check
            currentNonce = await provider.getTransactionCount(ownerWallet.address, 'pending');
            console.log(`   Final nonce: ${currentNonce}`);
        }
        
        const tx = await contract.togglePKI(enablePKI, {
            nonce: currentNonce  // Explicitly set nonce
        });
        console.log(`   Transaction hash: ${tx.hash}`);
        
        await tx.wait();
        console.log(`   ✅ PKI ${enablePKI ? 'enabled' : 'disabled'} successfully`);
        
        // Verify
        const newPKIStatus = await contract.pkiEnabled();
        console.log(`   New PKI status: ${newPKIStatus}`);
        
    } catch (error) {
        console.error('\n❌ Failed to toggle PKI:', error.message);
        if (error.reason) {
            console.error('   Reason:', error.reason);
        }
        process.exit(1);
    }
}

if (require.main === module) {
    togglePKI().catch(console.error);
}

