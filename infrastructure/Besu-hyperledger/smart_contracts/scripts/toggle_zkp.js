const path = require('path');
const fs = require('fs-extra');
const https = require('https');
const ethers = require('ethers');

const host = process.env.RPC_ENDPOINT || 'http://127.0.0.1:21001';
const accountPrivateKey =
  process.env.PRIVATE_KEY ||
  '0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63';

const CA_CERT_PATH =
  process.env.CA_CERT_PATH ||
  path.resolve(__dirname, '../../config/tls/ca/certs/sbv-root-ca.crt');
const ALLOW_INSECURE_TLS = process.env.ALLOW_INSECURE_TLS === 'true';

const interbankJsonPath = path.resolve(
  __dirname,
  '../contracts',
  'InterbankTransfer.json'
);
const interbankAddressPath = path.resolve(
  __dirname,
  '../contracts',
  'InterbankTransfer.address.txt'
);

if (!fs.existsSync(interbankJsonPath)) {
  throw new Error(`Không tìm thấy InterbankTransfer.json tại: ${interbankJsonPath}`);
}
if (!fs.existsSync(interbankAddressPath)) {
  throw new Error(
    `Không tìm thấy InterbankTransfer.address.txt, hãy deploy InterbankTransfer trước`
  );
}

const interbankJson = JSON.parse(fs.readFileSync(interbankJsonPath));
const interbankAbi = interbankJson.abi;
const interbankAddress = fs.readFileSync(interbankAddressPath, 'utf8').trim();

const ENABLE_ZKP = process.env.ZKP_ENABLED !== 'false'; // mặc định bật

async function main() {
  try {
    console.log('RPC endpoint:', host);
    console.log('InterbankTransfer:', interbankAddress);
    console.log('Toggle ZKP to:', ENABLE_ZKP);

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
    const wallet = new ethers.Wallet(accountPrivateKey, provider);

    const interbank = new ethers.Contract(
      interbankAddress,
      interbankAbi,
      wallet
    );

    console.log('Calling toggleZKP(...) on InterbankTransfer...');
    const tx = await interbank.toggleZKP(ENABLE_ZKP, {
      gasLimit: 2000000,
      gasPrice: 0
    });
    console.log('Tx hash:', tx.hash);
    await tx.wait();
    console.log('✅ ZKP flag updated. Current state should be enabled:', ENABLE_ZKP);
  } catch (err) {
    console.error('❌ toggle_zkp.js failed:', err);
    process.exit(1);
  }
}

if (require.main === module) {
  main();
}


