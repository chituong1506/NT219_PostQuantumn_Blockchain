const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');
const https = require('https');

const RPC_ENDPOINT = process.env.RPC_ENDPOINT || "https://localhost:21001";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

const USERS_TO_FUND = [
    "0x6423CfdF2B3E2E94613266631f22EA0e8788e34e", // VCB User 1
    "0x1444808f0AfF7ec6008A416450Dd4e14069d436D", // VCB User 2
    "0x469Bb95e092005ba56a786fAAAE10BA38285E1c8", // VTB User 1
    "0x2e27a0742fbbF51245b606DF46165e7eFa412b7C", // VTB User 2
    "0x12B7D41e4Cf1f380a838067127a32E30B42b3e73", // BIDV User 1
    "0x21f0e22d5974Ecd5EDC1efDF1135A39Ff1474E9D", // BIDV User 2
];

async function fundUsers() {
    console.log("Funding users for PKI registration...\n");
    
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
    
    console.log(`Funding from: ${wallet.address}`);
    const funderBalance = await provider.getBalance(wallet.address);
    console.log(`Funder balance: ${ethers.formatEther(funderBalance)} ETH\n`);
    
    const amount = ethers.parseEther("1"); // 1 ETH per user (enough for gas)
    
    for (const userAddress of USERS_TO_FUND) {
        try {
            const balance = await provider.getBalance(userAddress);
            if (balance > 0n) {
                console.log(`⏭️  ${userAddress} already has ${ethers.formatEther(balance)} ETH`);
                continue;
            }
            
            console.log(`💰 Funding ${userAddress}...`);
            const tx = await wallet.sendTransaction({
                to: userAddress,
                value: amount,
                gasLimit: 21000,
                gasPrice: 0
            });
            await tx.wait();
            console.log(`   ✅ Sent 1 ETH (tx: ${tx.hash})`);
        } catch (error) {
            console.error(`   ❌ Failed: ${error.message}`);
        }
    }
    
    console.log("\n✅ Funding complete!");
}

fundUsers().catch(console.error);
