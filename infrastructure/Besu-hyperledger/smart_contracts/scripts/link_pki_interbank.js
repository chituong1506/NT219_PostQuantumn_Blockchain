const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');

// Configuration
const RPC_ENDPOINT = process.env.RPC_ENDPOINT || "http://localhost:21001";
const PRIVATE_KEY = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

async function linkContracts() {
    console.log("========================================");
    console.log("Linking PKI Registry to InterbankTransfer");
    console.log("========================================\n");
    
    // Setup
    const provider = new ethers.JsonRpcProvider(RPC_ENDPOINT);
    const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
    
    console.log(`Using wallet: ${wallet.address}\n`);
    
    // Load PKI Registry address
    const pkiAddressPath = path.resolve(__dirname, '../contracts/PKIRegistry.address.txt');
    if (!fs.existsSync(pkiAddressPath)) {
        console.error("❌ PKI Registry not deployed! Run: node scripts/deploy_pki.js");
        process.exit(1);
    }
    const pkiAddress = fs.readFileSync(pkiAddressPath, 'utf8').trim();
    console.log(`✅ PKI Registry: ${pkiAddress}`);
    
    // Load InterbankTransfer address
    const interbankAddressPath = path.resolve(__dirname, '../contracts/InterbankTransfer.address.txt');
    if (!fs.existsSync(interbankAddressPath)) {
        console.error("❌ InterbankTransfer not deployed! Run: node scripts/public/deploy_and_init.js");
        process.exit(1);
    }
    const interbankAddress = fs.readFileSync(interbankAddressPath, 'utf8').trim();
    console.log(`✅ InterbankTransfer: ${interbankAddress}\n`);
    
    // Load contract ABIs
    const interbankJson = JSON.parse(
        fs.readFileSync(path.resolve(__dirname, '../contracts/InterbankTransfer.json'), 'utf8')
    );
    
    // Connect to InterbankTransfer
    const interbank = new ethers.Contract(interbankAddress, interbankJson.abi, wallet);
    
    // Step 1: Set PKI Registry in InterbankTransfer
    console.log("🔗 Step 1: Linking PKI Registry to InterbankTransfer...");
    try {
        const tx = await interbank.setPKIRegistry(pkiAddress);
        console.log(`  Transaction sent: ${tx.hash}`);
        await tx.wait();
        console.log(`  ✅ PKI Registry linked!`);
        
        // Verify
        const linkedPKI = await interbank.pkiRegistry();
        const pkiEnabled = await interbank.pkiEnabled();
        console.log(`  ✅ Verified: PKI = ${linkedPKI}`);
        console.log(`  ✅ PKI Enabled: ${pkiEnabled}\n`);
    } catch (error) {
        console.error(`  ❌ Failed: ${error.message}\n`);
        process.exit(1);
    }
    
    // Step 2: Update GUI config
    console.log("📝 Step 2: Updating GUI configuration...");
    await updateGUIConfig(pkiAddress, interbankAddress);
    
    // Step 3: Test integration
    console.log("\n🧪 Step 3: Testing PKI integration...");
    await testIntegration(interbank);
    
    console.log("\n========================================");
    console.log("✅ PKI Integration Complete!");
    console.log("========================================");
    console.log("\n📋 Summary:");
    console.log(`  PKI Registry: ${pkiAddress}`);
    console.log(`  InterbankTransfer: ${interbankAddress}`);
    console.log(`  PKI Enabled: Yes`);
    console.log("\n📌 Next Steps:");
    console.log("  1. Test transfer with PKI: node scripts/test_pki_transfer.js");
    console.log("  2. Run GUI: cd ../../GUI/web && npm run dev");
}

async function updateGUIConfig(pkiAddress, interbankAddress) {
    const guiConfigPath = path.resolve(__dirname, '../../../GUI/web/config/contracts.ts');
    
    if (!fs.existsSync(guiConfigPath)) {
        console.warn("  ⚠️  GUI config not found");
        return;
    }
    
    let config = fs.readFileSync(guiConfigPath, 'utf8');
    
    // Ensure PKI_REGISTRY_ADDRESS exists
    if (!config.includes('PKI_REGISTRY_ADDRESS')) {
        config = config.replace(
            /export const/,
            `export const PKI_REGISTRY_ADDRESS = '${pkiAddress}';\n\nexport const`
        );
    } else {
        config = config.replace(
            /PKI_REGISTRY_ADDRESS = '.*'/,
            `PKI_REGISTRY_ADDRESS = '${pkiAddress}'`
        );
    }
    
    // Update INTERBANK_TRANSFER_ADDRESS if needed
    if (config.includes('INTERBANK_TRANSFER_ADDRESS')) {
        config = config.replace(
            /INTERBANK_TRANSFER_ADDRESS = '.*'/,
            `INTERBANK_TRANSFER_ADDRESS = '${interbankAddress}'`
        );
    }
    
    fs.writeFileSync(guiConfigPath, config);
    console.log("  ✅ GUI config updated");
}

async function testIntegration(contract) {
    try {
        // Test 1: Check PKI is enabled
        const pkiEnabled = await contract.pkiEnabled();
        console.log(`  ✅ Test 1: PKI Enabled = ${pkiEnabled}`);
        
        // Test 2: Try to get getUserPublicKey function
        const hasFunction = contract.interface.hasFunction('getUserPublicKey');
        console.log(`  ✅ Test 2: getUserPublicKey exists = ${hasFunction}`);
        
        // Test 3: Check checkTransferAuthorization function
        const hasAuthCheck = contract.interface.hasFunction('checkTransferAuthorization');
        console.log(`  ✅ Test 3: checkTransferAuthorization exists = ${hasAuthCheck}`);
        
    } catch (error) {
        console.error(`  ❌ Test failed: ${error.message}`);
    }
}

// Main execution
linkContracts()
    .then(() => process.exit(0))
    .catch(error => {
        console.error("\n❌ Linking failed:");
        console.error(error);
        process.exit(1);
    });

