const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');

// Configuration
const RPC_ENDPOINT = process.env.RPC_ENDPOINT || "http://localhost:21001";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// Bank addresses from genesis (accounts with private keys)
const BANK_ADDRESSES = {
    SBV: "0xf17f52151EbEF6C7334FAD080c5704D77216b732",      // Account C from genesis
    VCB: "0x627306090abaB3A6e1400e9345bC60c78a8BEf57",      // Account B from genesis  
    VTB: "0xfe3b557e8fb62b89f4916b721be55ceb828dbd73",      // Account A (owner)
    BIDV: "0xf0e2db6c8dc6c681bb5d6ad121a107f300e9b2b5",     // Member1 from besu accounts
};

// Bank private keys (from genesis and keys.js)
const BANK_PRIVATE_KEYS = {
    SBV: "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f",
    VCB: "0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3",
    VTB: "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63",
    BIDV: "0x8bbbb1b345af56b560a5b20bd4b0ed1cd8cc9958a16262bc75118453cb546df7",
};

async function deploy() {
    console.log("========================================");
    console.log("PKI Registry Contract Deployment");
    console.log("========================================");
    console.log(`RPC Endpoint: ${RPC_ENDPOINT}\n`);
    
    // Setup provider
    const provider = new ethers.JsonRpcProvider(RPC_ENDPOINT);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    console.log(`Deploying from: ${wallet.address}`);
    
    // Load compiled contract
    const contractPath = path.resolve(__dirname, '../contracts/PKIRegistry.json');
    
    if (!fs.existsSync(contractPath)) {
        console.error("❌ Contract not compiled! Run: node scripts/compile.js");
        process.exit(1);
    }
    
    const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
    const abi = contractJson.abi;
    const bytecode = contractJson.evm.bytecode.object;
    
    // Deploy
    console.log("\n📦 Deploying PKIRegistry contract...");
    const factory = new ethers.ContractFactory(abi, bytecode, wallet);
    const contract = await factory.deploy();
    
    await contract.waitForDeployment();
    const address = await contract.getAddress();
    
    console.log(`✅ Contract deployed at: ${address}`);
    
    // Save address
    const addressPath = path.resolve(__dirname, '../contracts/PKIRegistry.address.txt');
    fs.writeFileSync(addressPath, address);
    console.log(`✅ Address saved to: ${addressPath}`);
    
    // Initialize: Authorize banks
    console.log("\n🔐 Authorizing banks...");
    for (const [name, addr] of Object.entries(BANK_ADDRESSES)) {
        try {
            const tx = await contract.authorizeBankAddress(addr, true);
            await tx.wait();
            console.log(`✅ ${name} authorized: ${addr}`);
        } catch (error) {
            console.error(`❌ Failed to authorize ${name}:`, error.message);
        }
    }
    
    // Register test users with PQC keys
    console.log("\n👤 Registering test users...");
    await registerTestUsers(contract, wallet);
    
    // Update GUI config
    await updateGUIConfig(address);
    
    // Verify deployment
    await verifyDeployment(contract);
    
    console.log("\n========================================");
    console.log("✅ PKI Registry Deployment Complete!");
    console.log("========================================");
    console.log(`\nContract Address: ${address}`);
    console.log(`Total Authorized Banks: ${Object.keys(BANK_ADDRESSES).length}`);
}

async function registerTestUsers(contract, wallet) {
    // Use bank accounts as test users (they have balances)
    // In production, users would be separate from banks
    const testUsers = [
        {
            name: "SBV_User",
            address: "0xf17f52151EbEF6C7334FAD080c5704D77216b732",  // SBV bank  
            privateKey: "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f",
            bank: "VCB"  // VCB will verify SBV's KYC
        },
        {
            name: "BIDV_User", 
            address: "0xf0e2db6c8dc6c681bb5d6ad121a107f300e9b2b5",  // BIDV bank
            privateKey: "0x8bbbb1b345af56b560a5b20bd4b0ed1cd8cc9958a16262bc75118453cb546df7",
            bank: "VTB"  // VTB will verify BIDV's KYC
        }
    ];
    
    for (const user of testUsers) {
        try {
            console.log(`\n📝 Setting up ${user.name}...`);
            
            // Step 1: User registers themselves
            const userWallet = new ethers.Wallet(user.privateKey, wallet.provider);
            const userContract = contract.connect(userWallet);
            
            // Check user balance first
            const userBalance = await wallet.provider.getBalance(user.address);
            console.log(`   Balance: ${ethers.formatEther(userBalance)} ETH`);
            
            // Generate mock PQC public key (1952 bytes for Dilithium3)
            const mockPublicKey = ethers.hexlify(ethers.randomBytes(1952));
            
            const registerTx = await userContract.registerUser(mockPublicKey, {
                gasLimit: 5000000
            });
            const registerReceipt = await registerTx.wait();
            
            if (registerReceipt.status !== 1) {
                console.error(`   ❌ Registration failed!`);
                continue;
            }
            console.log(`   ✅ Self-registered: ${user.address}`);
            
            // Wait for 1 more block
            const currentBlock = await wallet.provider.getBlockNumber();
            while ((await wallet.provider.getBlockNumber()) === currentBlock) {
                await new Promise(resolve => setTimeout(resolve, 1000));
            }
            
            // Step 2: Bank verifies KYC
            const bankPrivateKey = BANK_PRIVATE_KEYS[user.bank];
            const bankWallet = new ethers.Wallet(bankPrivateKey, wallet.provider);
            const bankContract = contract.connect(bankWallet);
            
            const kycHash = ethers.keccak256(ethers.toUtf8Bytes(`KYC_${user.name}`));
            const kycTx = await bankContract.verifyKYC(user.address, kycHash, 365, {
                gasLimit: 5000000
            });
            await kycTx.wait();
            console.log(`   ✅ KYC verified by ${user.bank}`);
            
            // Step 3: Bank sets authorization
            const authTx = await bankContract.setAuthorization(
                user.address,
                true,  // canTransfer
                true,  // canReceive
                ethers.parseEther("100"),  // 100 ETH daily limit
                {
                    gasLimit: 5000000
                }
            );
            await authTx.wait();
            console.log(`   ✅ Authorization set (100 ETH daily limit)`);
            
        } catch (error) {
            console.error(`❌ Failed to setup ${user.name}:`, error.shortMessage || error.message);
        }
    }
}

async function updateGUIConfig(contractAddress) {
    const guiConfigPath = path.resolve(__dirname, '../../../GUI/web/config/contracts.ts');
    
    if (!fs.existsSync(guiConfigPath)) {
        console.warn("⚠️  GUI config not found, skipping update");
        return;
    }
    
    let config = fs.readFileSync(guiConfigPath, 'utf8');
    
    // Add PKI_REGISTRY_ADDRESS
    if (!config.includes('PKI_REGISTRY_ADDRESS')) {
        config = config.replace(
            /export const/,
            `export const PKI_REGISTRY_ADDRESS = '${contractAddress}';\n\nexport const`
        );
    } else {
        config = config.replace(
            /PKI_REGISTRY_ADDRESS = '.*'/,
            `PKI_REGISTRY_ADDRESS = '${contractAddress}'`
        );
    }
    
    fs.writeFileSync(guiConfigPath, config);
    console.log("\n✅ GUI config updated");
}

async function verifyDeployment(contract) {
    console.log("\n🔍 Verifying deployment...");
    
    try {
        // Check owner
        const owner = await contract.owner();
        console.log(`✅ Owner: ${owner}`);
        
        // Check authorized banks
        for (const [name, addr] of Object.entries(BANK_ADDRESSES)) {
            const isAuthorized = await contract.authorizedBanks(addr);
            console.log(`  ${isAuthorized ? '✅' : '❌'} ${name}: ${isAuthorized}`);
        }
        
        // Check total users
        const totalUsers = await contract.totalUsers();
        console.log(`✅ Total registered users: ${totalUsers}`);
        
    } catch (error) {
        console.error("❌ Verification failed:", error.message);
    }
}

// Main execution
deploy()
    .then(() => process.exit(0))
    .catch(error => {
        console.error("\n❌ Deployment failed:");
        console.error(error);
        process.exit(1);
    });

