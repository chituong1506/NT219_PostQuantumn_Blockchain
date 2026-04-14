const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');
const https = require('https');

// Configuration
const RPC_ENDPOINT = process.env.RPC_ENDPOINT || "https://localhost:21001";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// Test users (đã được register trong deploy_pki.js)
const TEST_USERS = [
    {
        name: "SBV_User",
        address: "0xf17f52151EbEF6C7334FAD080c5704D77216b732",
        privateKey: "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f"
    },
    {
        name: "BIDV_User",
        address: "0xf0e2db6c8dc6c681bb5d6ad121a107f300e9b2b5",
        privateKey: "0x8bbbb1b345af56b560a5b20bd4b0ed1cd8cc9958a16262bc75118453cb546df7"
    }
];

// Use first test user
const TEST_USER = TEST_USERS[0];

async function testPKI() {
    console.log("========================================");
    console.log("PKI Registry Testing");
    console.log("========================================\n");
    
    // Setup provider with TLS support
    const providerOptions = RPC_ENDPOINT.startsWith('https') ? {
        fetchOptions: {
            agent: new https.Agent({
                rejectUnauthorized: false
            })
        }
    } : {};
    
    const provider = new ethers.JsonRpcProvider(RPC_ENDPOINT, undefined, providerOptions);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    // Load contract
    const contractPath = path.resolve(__dirname, '../contracts/PKIRegistry.json');
    const addressPath = path.resolve(__dirname, '../contracts/PKIRegistry.address.txt');
    
    if (!fs.existsSync(addressPath)) {
        console.error("❌ Contract not deployed! Run: node scripts/deploy_pki.js");
        process.exit(1);
    }
    
    const contractAddress = fs.readFileSync(addressPath, 'utf8').trim();
    const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
    const contract = new ethers.Contract(contractAddress, contractJson.abi, wallet);
    
    console.log(`Contract Address: ${contractAddress}`);
    console.log(`Test User: ${TEST_USER.name} (${TEST_USER.address})\n`);
    
    // Test 1: Get user info
    console.log("📋 Test 1: Get User Info");
    try {
        const userInfo = await contract.getUserInfo(TEST_USER.address);
        console.log("✅ User Identity:");
        console.log(`  Address: ${userInfo[0].userAddress}`);
        console.log(`  Key Hash: ${userInfo[0].keyHash}`);
        console.log(`  Active: ${userInfo[0].isActive}`);
        console.log(`  Registered: ${new Date(Number(userInfo[0].registeredAt) * 1000).toLocaleString()}`);
        
        console.log("\n✅ KYC Info:");
        console.log(`  Verified: ${userInfo[1].isVerified}`);
        console.log(`  Verified At: ${new Date(Number(userInfo[1].verifiedAt) * 1000).toLocaleString()}`);
        console.log(`  Expires At: ${new Date(Number(userInfo[1].expiresAt) * 1000).toLocaleString()}`);
        
        console.log("\n✅ Authorization:");
        console.log(`  Can Transfer: ${userInfo[2].canTransfer}`);
        console.log(`  Can Receive: ${userInfo[2].canReceive}`);
        console.log(`  Daily Limit: ${ethers.formatEther(userInfo[2].dailyLimit)} ETH`);
        console.log(`  Used Today: ${ethers.formatEther(userInfo[2].usedToday)} ETH`);
    } catch (error) {
        console.error("❌ Failed:", error.message);
    }
    
    // Test 2: Check KYC validity
    console.log("\n📋 Test 2: Check KYC Validity");
    try {
        const isValid = await contract.isKYCValid(TEST_USER.address);
        console.log(`✅ KYC Valid: ${isValid}`);
    } catch (error) {
        console.error("❌ Failed:", error.message);
    }
    
    // Test 3: Check transfer permission
    console.log("\n📋 Test 3: Check Transfer Permission");
    try {
        const amount = ethers.parseEther("10"); // 10 ETH
        const canTransfer = await contract.canUserTransfer(TEST_USER.address, amount);
        console.log(`✅ Can transfer 10 ETH: ${canTransfer}`);
        
        // Try exceeding daily limit
        const largeAmount = ethers.parseEther("200"); // 200 ETH (exceeds 100 ETH limit)
        const canTransferLarge = await contract.canUserTransfer(TEST_USER.address, largeAmount);
        console.log(`✅ Can transfer 200 ETH: ${canTransferLarge} (should be false)`);
    } catch (error) {
        console.error("❌ Failed:", error.message);
    }
    
    // Test 4: Get public key
    console.log("\n📋 Test 4: Get Public Key");
    try {
        const publicKey = await contract.getUserPublicKey(TEST_USER.address);
        console.log(`✅ Public Key (first 50 bytes): ${publicKey.slice(0, 100)}...`);
        console.log(`✅ Public Key Length: ${(publicKey.length - 2) / 2} bytes`);
    } catch (error) {
        console.error("❌ Failed:", error.message);
    }
    
    // Test 5: Record transfer (simulate)
    console.log("\n📋 Test 5: Record Transfer Usage");
    try {
        const amount = ethers.parseEther("5"); // 5 ETH
        const tx = await contract.recordTransfer(TEST_USER.address, amount);
        await tx.wait();
        console.log(`✅ Recorded transfer: 5 ETH`);
        
        // Check updated usage
        const userInfo = await contract.getUserInfo(TEST_USER.address);
        console.log(`✅ Used Today: ${ethers.formatEther(userInfo[2].usedToday)} ETH`);
    } catch (error) {
        console.error("❌ Failed:", error.message);
    }
    
    // Test 6: Key rotation
    console.log("\n📋 Test 6: Key Rotation");
    try {
        const userWallet = new ethers.Wallet(TEST_USER.privateKey, provider);
        const userContract = contract.connect(userWallet);
        
        // Generate new mock public key
        const newPublicKey = ethers.hexlify(ethers.randomBytes(1952));
        
        const tx = await userContract.updatePublicKey(newPublicKey);
        const receipt = await tx.wait();
        console.log(`✅ Public key rotated! Tx: ${receipt.hash}`);
        
        // Verify new key
        const updatedKey = await contract.getUserPublicKey(TEST_USER.address);
        console.log(`✅ New key confirmed: ${updatedKey.slice(0, 50)}...`);
    } catch (error) {
        console.error("❌ Failed:", error.message);
    }
    
    // Test 7: Get statistics
    console.log("\n📋 Test 7: Get Statistics");
    try {
        const totalUsers = await contract.totalUsers();
        console.log(`✅ Total Registered Users: ${totalUsers}`);
    } catch (error) {
        console.error("❌ Failed:", error.message);
    }
    
    console.log("\n========================================");
    console.log("✅ PKI Registry Testing Complete!");
    console.log("========================================");
}

// Main execution
testPKI()
    .then(() => process.exit(0))
    .catch(error => {
        console.error("\n❌ Testing failed:");
        console.error(error);
        process.exit(1);
    });

