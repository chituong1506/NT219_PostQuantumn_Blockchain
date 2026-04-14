const path = require('path');
const fs = require('fs-extra');
const ethers = require('ethers');
const { createProvider, createWallet, getTLSInfo } = require('../tls-provider');

// Import deploy và init functions
const { deployContract } = require('./deploy_interbank');
const { initializeContract } = require('./init_contract');

/**
 * Deploy contract và khởi tạo số dư cho tất cả users
 * Sử dụng khi reset blockchain hoặc setup mới
 */
async function deployAndInit() {
    console.log("🚀 Bắt đầu deploy contract và khởi tạo...\n");
    
    try {
        // Bước 1: Deploy contract
        console.log("=".repeat(60));
        console.log("BƯỚC 1: DEPLOY CONTRACT");
        console.log("=".repeat(60));
        const contractAddress = await deployContract();
        
        if (!contractAddress) {
            throw new Error("Deploy contract failed - no address returned");
        }
        
        console.log("\n✅ Contract deployed at:", contractAddress);
        
        // Cập nhật contract address trong init script
        process.env.CONTRACT_ADDRESS = contractAddress;
        
        // Bước 2: Initialize contract (authorize + deposit)
        console.log("\n" + "=".repeat(60));
        console.log("BƯỚC 2: KHỞI TẠO CONTRACT (Authorize + Deposit)");
        console.log("=".repeat(60));
        await initializeContract();
        
        // Bước 3: Lưu contract address vào GUI config
        console.log("\n" + "=".repeat(60));
        console.log("BƯỚC 3: CẬP NHẬT GUI CONFIG");
        console.log("=".repeat(60));
        await updateGUIConfig(contractAddress);
        
        console.log("\n" + "=".repeat(60));
        console.log("✅ HOÀN TẤT! Contract đã được deploy và khởi tạo thành công!");
        console.log("=".repeat(60));
        console.log("\n📋 Thông tin:");
        console.log(`   Contract Address: ${contractAddress}`);
        console.log(`   GUI Config đã được cập nhật tự động`);
        console.log("\n🚀 Bây giờ bạn có thể sử dụng contract trong GUI!");
        
    } catch (error) {
        console.error("\n❌ Lỗi:", error.message);
        throw error;
    }
}

/**
 * Cập nhật contract address trong GUI config
 */
async function updateGUIConfig(contractAddress) {
    // Try multiple possible paths (relative to script location)
    // Script is at: Besu-hyperledger/smart_contracts/scripts/public/deploy_and_init.js
    // GUI config is at: GUI/web/config/contracts.ts (at project root)
    const scriptDir = __dirname; // .../Besu-hyperledger/smart_contracts/scripts/public
    const possiblePaths = [
        path.resolve(scriptDir, '../../../../../', 'GUI', 'web', 'config', 'contracts.ts'), // Go up 5 levels to project root
        path.resolve(scriptDir, '../../../../', 'GUI', 'web', 'config', 'contracts.ts'), // Try 4 levels
        path.resolve(process.cwd(), 'GUI', 'web', 'config', 'contracts.ts'), // From current working directory
        '/home/quy/project/NT209_Project/GUI/web/config/contracts.ts', // Absolute path fallback
    ];
    
    let guiConfigPath = null;
    for (const p of possiblePaths) {
        if (fs.existsSync(p)) {
            guiConfigPath = p;
            break;
        }
    }
    
    if (!guiConfigPath) {
        // Try to find it using find command
        const { execSync } = require('child_process');
        try {
            const projectRoot = path.resolve(scriptDir, '../../../../');
            const found = execSync(`find "${projectRoot}" -path "*/GUI/web/config/contracts.ts" -type f 2>/dev/null | head -1`, { encoding: 'utf8' }).trim();
            if (found) {
                guiConfigPath = found;
            }
        } catch (e) {
            // Ignore
        }
    }
    
    try {
        if (!guiConfigPath || !fs.existsSync(guiConfigPath)) {
            console.warn(`⚠️  Không tìm thấy file GUI config`);
            console.log(`   Contract address: ${contractAddress}`);
            console.log(`   Hãy cập nhật thủ công trong GUI/web/config/contracts.ts`);
            return;
        }
        
        console.log(`   Tìm thấy GUI config tại: ${guiConfigPath}`);
        
        let content = fs.readFileSync(guiConfigPath, 'utf8');
        
        // Tìm và thay thế contract address
        const addressRegex = /export const INTERBANK_TRANSFER_ADDRESS\s*=\s*process\.env\.NEXT_PUBLIC_CONTRACT_ADDRESS\s*\|\|\s*['"](.*?)['"]/;
        const match = content.match(addressRegex);
        
        if (match) {
            // Thay thế address cũ bằng address mới
            content = content.replace(
                addressRegex,
                `export const INTERBANK_TRANSFER_ADDRESS = 
  process.env.NEXT_PUBLIC_CONTRACT_ADDRESS || '${contractAddress}'`
            );
            
            fs.writeFileSync(guiConfigPath, content, 'utf8');
            console.log(`✅ Đã cập nhật GUI config: ${guiConfigPath}`);
            console.log(`   Contract address mới: ${contractAddress}`);
        } else {
            console.warn(`⚠️  Không tìm thấy pattern để update trong GUI config`);
            console.log(`   Hãy cập nhật thủ công: ${contractAddress}`);
        }
        
    } catch (error) {
        console.error(`❌ Lỗi khi cập nhật GUI config:`, error.message);
        console.log(`   Hãy cập nhật thủ công contract address: ${contractAddress}`);
    }
}

async function main() {
    await deployAndInit()
        .then(() => {
            console.log("\n✅ Script hoàn thành!");
            process.exit(0);
        })
        .catch((error) => {
            console.error("\n❌ Script thất bại:", error.message);
            process.exit(1);
        });
}

if (require.main === module) {
    main();
}

module.exports = { deployAndInit };

