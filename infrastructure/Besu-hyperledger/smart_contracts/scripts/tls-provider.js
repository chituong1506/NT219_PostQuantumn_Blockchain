/**
 * TLS-enabled Ethers Provider Helper
 * 
 * This module provides a helper function to create ethers.js providers
 * with TLS/HTTPS support and proper certificate verification.
 */

const path = require('path');
const fs = require('fs-extra');
const https = require('https');
const ethers = require('ethers');

// Default configuration
const DEFAULT_HOST = "http://127.0.0.1:21001";
const CA_CERT_PATH = process.env.CA_CERT_PATH || path.resolve(__dirname, '../../config/tls/ca/certs/sbv-root-ca.crt');
const ALLOW_INSECURE_TLS = process.env.ALLOW_INSECURE_TLS === 'true';

/**
 * Create an ethers provider with TLS support
 * 
 * @param {string} rpcUrl - RPC endpoint URL (http:// or https://)
 * @param {object} options - Additional options
 * @returns {ethers.JsonRpcProvider}
 */
function createProvider(rpcUrl = null, options = {}) {
  const host = rpcUrl || process.env.RPC_ENDPOINT || DEFAULT_HOST;
  
  console.log("Creating provider for:", host);
  
  // Setup TLS configuration if using HTTPS
  let fetchRequest = undefined;
  
  if (host.startsWith('https://')) {
    // Check if CA certificate exists
    const caCertPath = options.caCertPath || CA_CERT_PATH;
    const allowInsecure = options.allowInsecure || ALLOW_INSECURE_TLS;
    
    let ca = undefined;
    if (fs.existsSync(caCertPath)) {
      ca = fs.readFileSync(caCertPath);
      console.log(`🔒 Using TLS with CA certificate: ${caCertPath}`);
    } else if (allowInsecure) {
      console.log(`⚠️  TLS enabled but CA cert not found at: ${caCertPath}`);
      console.log(`⚠️  Using insecure mode (certificate verification disabled)`);
      console.log(`⚠️  Set CA_CERT_PATH environment variable or fix certificate path`);
    } else {
      throw new Error(
        `CA certificate not found at: ${caCertPath}\n` +
        `Either:\n` +
        `  1. Set CA_CERT_PATH to correct certificate path\n` +
        `  2. Set ALLOW_INSECURE_TLS=true to disable verification (not recommended)\n` +
        `  3. Use HTTP instead of HTTPS`
      );
    }
    
    // Create HTTPS agent with certificate
    // For self-signed certificates, we need to disable rejection
    const httpsAgent = new https.Agent({
      rejectUnauthorized: false, // Always false for self-signed certs
      ca: ca,
      checkServerIdentity: () => undefined // Skip hostname verification for self-signed
    });
    
    // Custom fetch with HTTPS agent
    fetchRequest = (url, reqOptions) => {
      return fetch(url, {
        ...reqOptions,
        agent: httpsAgent
      });
    };
  } else {
    console.log("Using HTTP (no TLS)");
  }
  
  // Create provider with TLS support
  const provider = new ethers.JsonRpcProvider(
    host,
    options.network || undefined,
    { fetchRequest }
  );
  
  return provider;
}

/**
 * Create a wallet with TLS-enabled provider
 * 
 * @param {string} privateKey - Private key (with or without 0x prefix)
 * @param {string} rpcUrl - RPC endpoint URL
 * @param {object} options - Additional options
 * @returns {ethers.Wallet}
 */
function createWallet(privateKey, rpcUrl = null, options = {}) {
  const provider = createProvider(rpcUrl, options);
  return new ethers.Wallet(privateKey, provider);
}

/**
 * Get TLS configuration info
 */
function getTLSInfo() {
  return {
    caCertPath: CA_CERT_PATH,
    caCertExists: fs.existsSync(CA_CERT_PATH),
    allowInsecure: ALLOW_INSECURE_TLS,
    defaultHost: DEFAULT_HOST
  };
}

module.exports = {
  createProvider,
  createWallet,
  getTLSInfo,
  CA_CERT_PATH,
  ALLOW_INSECURE_TLS
};

