const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');
const https = require('https');

// Configuration
const RPC_ENDPOINT = process.env.RPC_ENDPOINT || "https://localhost:21001";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// All users from GUI config (banks.ts)
const ALL_USERS = [
    // VCB Users
    {
        name: "VCB User 1",
        address: "0x6423CfdF2B3E2E94613266631f22EA0e8788e34e",
        privateKey: "0x67e14b41e88fa8dd79cbd302134c17c2ff611248ed88efae528d6db8a1386596",
        bank: "VCB",
        verifier: "0x627306090abaB3A6e1400e9345bC60c78a8BEf57", // VCB bank address
        verifierPrivateKey: "0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"
    },
    {
        name: "VCB User 2",
        address: "0x1444808f0AfF7ec6008A416450Dd4e14069d436D",
        privateKey: "0x57acc05c004fe40f4cb76207542bfefaa8804df2896645634c7f44ae51932f5f",
        bank: "VCB",
        verifier: "0x627306090abaB3A6e1400e9345bC60c78a8BEf57",
        verifierPrivateKey: "0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"
    },
    // VTB Users
    {
        name: "VTB User 1",
        address: "0x469Bb95e092005ba56a786fAAAE10BA38285E1c8",
        privateKey: "0xac07a9f152fe78a5ad89946a4794260818b05c7898b669666c0369304b5d4ab0",
        bank: "VTB",
        verifier: "0xfe3b557e8fb62b89f4916b721be55ceb828dbd73", // VTB bank address (owner)
        verifierPrivateKey: "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
    },
    {
        name: "VTB User 2",
        address: "0x2e27a0742fbbF51245b606DF46165e7eFa412b7C",
        privateKey: "0x5758fa2ccfc934d34a52728d9d968d93405eee22dd92328b31e8e9dca27251e3",
        bank: "VTB",
        verifier: "0xfe3b557e8fb62b89f4916b721be55ceb828dbd73",
        verifierPrivateKey: "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63"
    },
    // BIDV Users
    {
        name: "BIDV User 1",
        address: "0x12B7D41e4Cf1f380a838067127a32E30B42b3e73",
        privateKey: "0x7581b1943d30d3354c5b63e4aed6759aa61430fae5ca965a7e3ec5c18597e3a1",
        bank: "BIDV",
        verifier: "0xf0e2db6c8dc6c681bb5d6ad121a107f300e9b2b5", // BIDV bank address
        verifierPrivateKey: "0x8bbbb1b345af56b560a5b20bd4b0ed1cd8cc9958a16262bc75118453cb546df7"
    },
    {
        name: "BIDV User 2",
        address: "0x21f0e22d5974Ecd5EDC1efDF1135A39Ff1474E9D",
        privateKey: "0x5d88bec4d4783e2038f452ff6b371ab30774941503be01ea9c6296a7d8638d01",
        bank: "BIDV",
        verifier: "0xf0e2db6c8dc6c681bb5d6ad121a107f300e9b2b5",
        verifierPrivateKey: "0x8bbbb1b345af56b560a5b20bd4b0ed1cd8cc9958a16262bc75118453cb546df7"
    },
    // SBV (already registered, but include for completeness)
    {
        name: "SBV User",
        address: "0xf17f52151EbEF6C7334FAD080c5704D77216b732",
        privateKey: "0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f",
        bank: "SBV",
        verifier: "0x627306090abaB3A6e1400e9345bC60c78a8BEf57", // VCB verifies SBV
        verifierPrivateKey: "0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3"
    }
];

async function waitForNextBlock(provider) {
    const currentBlock = await provider.getBlockNumber();
    while ((await provider.getBlockNumber()) === currentBlock) {
        await new Promise(resolve => setTimeout(resolve, 1000));
    }
}

async function registerAllUsers() {
    console.log("========================================");
    console.log("Register All Users in PKI Registry");
    console.log("========================================");
    console.log(`RPC Endpoint: ${RPC_ENDPOINT}\n`);
    
    // Setup provider with TLS support (same as other scripts)
    let fetchRequest = undefined;
    if (RPC_ENDPOINT.startsWith('https://')) {
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
    
    const provider = new ethers.JsonRpcProvider(RPC_ENDPOINT, undefined, { 
        fetchRequest,
        ensAddress: null  // Disable ENS resolution for private networks
    });
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    // Load PKI Registry contract
    const contractPath = path.resolve(__dirname, '../contracts/PKIRegistry.json');
    const addressPath = path.resolve(__dirname, '../contracts/PKIRegistry.address.txt');
    
    if (!fs.existsSync(contractPath)) {
        console.error("❌ Contract not compiled! Run: node scripts/compile.js");
        process.exit(1);
    }
    
    if (!fs.existsSync(addressPath)) {
        console.error("❌ PKI Registry not deployed! Run: node scripts/deploy_pki.js");
        process.exit(1);
    }
    
    const contractAddress = fs.readFileSync(addressPath, 'utf8').trim();
    const contractJson = JSON.parse(fs.readFileSync(contractPath, 'utf8'));
    const contract = new ethers.Contract(contractAddress, contractJson.abi, wallet);
    
    console.log(`PKI Registry Address: ${contractAddress}\n`);
    
    let successCount = 0;
    let skipCount = 0;
    let failCount = 0;
    
    for (const user of ALL_USERS) {
        try {
            console.log(`\n📝 Processing ${user.name} (${user.address})...`);
            
            // Check if already registered
            try {
                const userInfo = await contract.getUserInfo(user.address);
                if (userInfo && userInfo[0].userAddress !== ethers.ZeroAddress) {
                    console.log(`   ⏭️  Already registered, skipping...`);
                    skipCount++;
                    continue;
                }
            } catch (e) {
                // User not registered, continue
            }
            
            // Check user balance
            const userBalance = await provider.getBalance(user.address);
            console.log(`   Balance: ${ethers.formatEther(userBalance)} ETH`);
            
            if (userBalance === 0n) {
                console.log(`   ⚠️  No balance, skipping...`);
                skipCount++;
                continue;
            }
            
            // Step 1: User self-registers
            const userWallet = new ethers.Wallet(user.privateKey, provider);
            const userContract = contract.connect(userWallet);
            const mockPublicKey = ethers.hexlify(ethers.randomBytes(1952));
            
            const registerTx = await userContract.registerUser(mockPublicKey, {
                gasLimit: 5000000,
                gasPrice: 0
            });
            const registerReceipt = await registerTx.wait();
            
            if (registerReceipt.status !== 1) {
                console.error(`   ❌ Registration failed!`);
                failCount++;
                continue;
            }
            
            console.log(`   ✅ Self-registered`);
            console.log(`   Tx hash: ${registerReceipt.hash}`);
            
            // Wait for next block
            await waitForNextBlock(provider);
            
            // Step 2: Bank verifies KYC
            const verifierWallet = new ethers.Wallet(user.verifierPrivateKey, provider);
            const verifierContract = contract.connect(verifierWallet);
            const kycHash = ethers.keccak256(ethers.toUtf8Bytes(`KYC_Data_for_${user.name}`));
            
            const kycTx = await verifierContract.verifyKYC(user.address, kycHash, 365, {
                gasLimit: 5000000,
                gasPrice: 0
            });
            await kycTx.wait();
            console.log(`   ✅ KYC verified by ${user.bank}`);
            
            // Step 3: Bank sets authorization
            const authTx = await verifierContract.setAuthorization(
                user.address,
                true,  // canTransfer
                true,  // canReceive
                ethers.parseEther("100"), // 100 ETH daily limit
                {
                    gasLimit: 5000000,
                    gasPrice: 0
                }
            );
            await authTx.wait();
            console.log(`   ✅ Authorization set (100 ETH daily limit)`);
            
            successCount++;
            
        } catch (error) {
            console.error(`   ❌ Failed to setup ${user.name}:`, error.message);
            failCount++;
        }
    }
    
    console.log("\n========================================");
    console.log("✅ Registration Complete!");
    console.log("========================================");
    console.log(`   Success: ${successCount}`);
    console.log(`   Skipped: ${skipCount}`);
    console.log(`   Failed: ${failCount}`);
    console.log(`   Total: ${ALL_USERS.length}`);
}

registerAllUsers().catch(console.error);

