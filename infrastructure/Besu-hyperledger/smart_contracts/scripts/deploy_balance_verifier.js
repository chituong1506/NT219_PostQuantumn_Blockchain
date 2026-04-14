const path = require('path');
const fs = require('fs-extra');
const https = require('https');
const ethers = require('ethers');

// RPC endpoint (HTTP hoặc HTTPS)
const host = process.env.RPC_ENDPOINT || 'http://127.0.0.1:21001';
const accountPrivateKey =
  process.env.PRIVATE_KEY ||
  '0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63';

// TLS Configuration (giống deploy_interbank.js)
const CA_CERT_PATH =
  process.env.CA_CERT_PATH ||
  path.resolve(__dirname, '../../config/tls/ca/certs/sbv-root-ca.crt');
const ALLOW_INSECURE_TLS = process.env.ALLOW_INSECURE_TLS === 'true';

const contractJsonPath = path.resolve(
  __dirname,
  '../contracts',
  'BalanceVerifier.json'
);

if (!fs.existsSync(contractJsonPath)) {
  throw new Error(`Không tìm thấy file contract tại: ${contractJsonPath}`);
}

const contractJson = JSON.parse(fs.readFileSync(contractJsonPath));
const contractAbi = contractJson.abi;

let contractBytecode = contractJson.evm.bytecode.object;
if (!contractBytecode.startsWith('0x')) {
  contractBytecode = '0x' + contractBytecode;
}

async function deployBalanceVerifier() {
  try {
    console.log('Connecting to blockchain at:', host);

    let fetchRequest = undefined;
    if (host.startsWith('https://')) {
      const httpsAgent = new https.Agent({
        rejectUnauthorized: !ALLOW_INSECURE_TLS,
        ca: fs.existsSync(CA_CERT_PATH)
          ? fs.readFileSync(CA_CERT_PATH)
          : undefined
      });

      fetchRequest = (url, options) =>
        fetch(url, {
          ...options,
          agent: httpsAgent
        });
    }

    const provider = new ethers.JsonRpcProvider(host, undefined, {
      fetchRequest
    });

    const network = await provider.getNetwork();
    console.log(
      `✅ Connected to network: ${network.name} (Chain ID: ${network.chainId})`
    );

    const wallet = new ethers.Wallet(accountPrivateKey, provider);
    console.log('Deployer address:', wallet.address);

    const balance = await provider.getBalance(wallet.address);
    console.log('Deployer balance:', ethers.formatEther(balance), 'ETH');

    const factory = new ethers.ContractFactory(
      contractAbi,
      contractBytecode,
      wallet
    );

    console.log('Deploying BalanceVerifier contract...');
    const contract = await factory.deploy({
      gasLimit: 6000000,
      gasPrice: 0
    });

    console.log('Deployment tx hash:', contract.deploymentTransaction().hash);
    await contract.waitForDeployment();
    const contractAddress = await contract.getAddress();

    console.log('✅ BalanceVerifier deployed at:', contractAddress);

    const outputDir = path.resolve(__dirname, '../contracts');
    if (fs.existsSync(outputDir)) {
      const addressFile = path.join(outputDir, 'BalanceVerifier.address.txt');
      fs.writeFileSync(addressFile, contractAddress);
      console.log('✅ Address saved to:', addressFile);
    }

    return contractAddress;
  } catch (err) {
    console.error('❌ Failed to deploy BalanceVerifier:', err);
    throw err;
  }
}

async function main() {
  try {
    await deployBalanceVerifier();
    console.log('✅ deploy_balance_verifier.js completed');
    process.exit(0);
  } catch (e) {
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}

module.exports = { deployBalanceVerifier };


