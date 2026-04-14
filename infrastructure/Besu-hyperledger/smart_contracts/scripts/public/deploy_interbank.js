const path = require('path');
const fs = require('fs-extra');
const https = require('https');
var ethers = require('ethers');

// RPCNODE details - sử dụng port 21001 (sbv container)
const { tessera, besu } = require("../keys.js");
// Note: Support both HTTP and HTTPS (TLS)
const host = process.env.RPC_ENDPOINT || "http://127.0.0.1:21001";
// Sử dụng private key của một account có balance (từ genesis)
const accountPrivateKey = process.env.PRIVATE_KEY || "0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63";

// TLS Configuration
const CA_CERT_PATH = process.env.CA_CERT_PATH || path.resolve(__dirname, '../../../config/tls/ca/certs/sbv-root-ca.crt');
const ALLOW_INSECURE_TLS = process.env.ALLOW_INSECURE_TLS === 'true';

// Contract path
const contractJsonPath = path.resolve(__dirname, '../../','contracts','InterbankTransfer.json');

// Kiểm tra file tồn tại
if (!fs.existsSync(contractJsonPath)) {
    throw new Error(`Không tìm thấy file contract tại: ${contractJsonPath}`);
}

console.log("Checking file path:", contractJsonPath);
const contractJson = JSON.parse(fs.readFileSync(contractJsonPath));
const contractAbi = contractJson.abi;

// FIX LỖI 1: Thêm '0x' nếu bytecode chưa có prefix
let contractBytecode = contractJson.evm.bytecode.object;
if (!contractBytecode.startsWith('0x')) {
    contractBytecode = "0x" + contractBytecode;
    console.log("✅ Đã thêm prefix '0x' vào bytecode");
}

async function deployContract() {
  try {
    console.log("Connecting to blockchain at:", host);
    
    // Setup TLS configuration if using HTTPS
    let fetchRequest = undefined;
    if (host.startsWith('https://')) {
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
    
    const provider = new ethers.JsonRpcProvider(host, undefined, { fetchRequest });
    
    // Kiểm tra kết nối mạng
    try {
        const network = await provider.getNetwork();
        console.log(`✅ Connected to network: ${network.name} (Chain ID: ${network.chainId})`);
    } catch (netError) {
        throw new Error(`❌ Không thể kết nối tới Node RPC tại ${host}. Hãy chắc chắn Node/Container đang chạy.`);
    }
    
    const wallet = new ethers.Wallet(accountPrivateKey, provider);
    console.log("Deployer address:", wallet.address);
    
    // Check balance
    const balance = await provider.getBalance(wallet.address);
    console.log("Deployer balance:", ethers.formatEther(balance), "ETH");
    
    if (balance === 0n) {
        console.warn("⚠️ Cảnh báo: Deployer balance = 0. Có thể không đủ gas để deploy!");
    }
    
    console.log("Deploying InterbankTransfer contract...");
    console.log("Bytecode length:", contractBytecode.length, "characters");
    
    const factory = new ethers.ContractFactory(contractAbi, contractBytecode, wallet);
    
    // Deploy contract (constructor không cần params)
    const contract = await factory.deploy({
      gasLimit: 15000000, // Max gas limit (block limit is 16,243,360)
      gasPrice: 0, // Free gas for private network
    });
    
    console.log("Transaction hash:", contract.deploymentTransaction().hash);
    console.log("Waiting for deployment...");
    
    // Ethers v6 syntax
    await contract.waitForDeployment();
    const contractAddress = await contract.getAddress();
    
    console.log("\n✅ Contract deployed successfully!");
    console.log("Contract Address:", contractAddress);
    
    // Lưu file address (đảm bảo thư mục tồn tại trước khi ghi)
    const outputDir = path.resolve(__dirname, '../../', 'contracts');
    if (fs.existsSync(outputDir)) {
        const addressFile = path.join(outputDir, 'InterbankTransfer.address.txt');
        fs.writeFileSync(addressFile, contractAddress);
        console.log("\n✅ Contract address saved to:", addressFile);
    } else {
        console.log("\n⚠️ Không tìm thấy thư mục contracts để lưu file address.");
    }
    
    console.log("\n📋 Next steps:");
    console.log("1. Set environment variable:");
    console.log(`   export NEXT_PUBLIC_CONTRACT_ADDRESS="${contractAddress}"`);
    console.log("\n2. Hoặc update trong GUI/web/config/contracts.ts:");
    console.log(`   export const INTERBANK_TRANSFER_ADDRESS = "${contractAddress}";`);
    
    return contractAddress;
  } catch (error) {
    console.error("❌ Deployment failed detail:", error);
    if (error.message) {
        console.error("Error message:", error.message);
    }
    if (error.code) {
        console.error("Error code:", error.code);
    }
    throw error;
  }
}

async function main(){
  await deployContract()
    .then(() => {
      console.log("\n✅ Deployment completed!");
      process.exit(0);
    })
    .catch((error) => {
      console.error("\n❌ Deployment failed:", error.message);
      process.exit(1);
    });
}

if (require.main === module) {
  main();
}

module.exports = exports = { deployContract };

