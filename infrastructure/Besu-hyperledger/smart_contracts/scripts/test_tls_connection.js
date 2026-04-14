/**
 * Test TLS Connection to Besu Node
 * 
 * Usage:
 *   node scripts/test_tls_connection.js
 *   RPC_ENDPOINT=https://localhost:21001 node scripts/test_tls_connection.js
 *   ALLOW_INSECURE_TLS=true node scripts/test_tls_connection.js
 */

const { createProvider, getTLSInfo } = require('./tls-provider');

async function testConnection() {
  console.log("🔍 Testing TLS Connection to Besu Node\n");
  
  // Show TLS configuration
  const tlsInfo = getTLSInfo();
  console.log("TLS Configuration:");
  console.log("  CA Certificate Path:", tlsInfo.caCertPath);
  console.log("  CA Certificate Exists:", tlsInfo.caCertExists ? "✅ Yes" : "❌ No");
  console.log("  Allow Insecure TLS:", tlsInfo.allowInsecure ? "⚠️  Yes (not recommended)" : "✅ No");
  console.log("  Default Host:", tlsInfo.defaultHost);
  console.log();
  
  try {
    // Create provider (will use RPC_ENDPOINT env var or default)
    const provider = createProvider();
    
    console.log("Testing connection...");
    
    // Test 1: Get network info
    console.log("\n📡 Test 1: Get Network Info");
    const network = await provider.getNetwork();
    console.log("  ✅ Network Name:", network.name);
    console.log("  ✅ Chain ID:", network.chainId.toString());
    
    // Test 2: Get block number
    console.log("\n📦 Test 2: Get Block Number");
    const blockNumber = await provider.getBlockNumber();
    console.log("  ✅ Current Block:", blockNumber);
    
    // Test 3: Get latest block
    console.log("\n🔗 Test 3: Get Latest Block");
    const block = await provider.getBlock('latest');
    console.log("  ✅ Block Hash:", block.hash);
    console.log("  ✅ Block Timestamp:", new Date(block.timestamp * 1000).toISOString());
    console.log("  ✅ Transactions:", block.transactions.length);
    
    // Test 4: Get gas price
    console.log("\n⛽ Test 4: Get Gas Price");
    const feeData = await provider.getFeeData();
    console.log("  ✅ Gas Price:", feeData.gasPrice ? feeData.gasPrice.toString() : "0 (free)");
    
    console.log("\n" + "=".repeat(60));
    console.log("✅ ALL TESTS PASSED - Connection successful!");
    console.log("=".repeat(60));
    
    return true;
    
  } catch (error) {
    console.error("\n" + "=".repeat(60));
    console.error("❌ CONNECTION FAILED");
    console.error("=".repeat(60));
    console.error("\nError:", error.message);
    
    if (error.message.includes('certificate')) {
      console.error("\n💡 TLS Certificate Issue Detected");
      console.error("\nPossible solutions:");
      console.error("  1. Check CA certificate path:");
      console.error(`     CA_CERT_PATH=${tlsInfo.caCertPath}`);
      console.error("  2. Generate TLS certificates:");
      console.error("     cd ../.. && ./scripts/generate_tls13_certs.sh");
      console.error("  3. Use insecure mode (not recommended):");
      console.error("     ALLOW_INSECURE_TLS=true node scripts/test_tls_connection.js");
      console.error("  4. Use HTTP instead:");
      console.error("     RPC_ENDPOINT=http://localhost:21001 node scripts/test_tls_connection.js");
    } else if (error.message.includes('ECONNREFUSED') || error.message.includes('fetch failed')) {
      console.error("\n💡 Connection Refused");
      console.error("\nPossible solutions:");
      console.error("  1. Check if Besu node is running:");
      console.error("     docker ps | grep besu");
      console.error("  2. Check if port is correct:");
      console.error("     RPC_ENDPOINT=http://localhost:21001 (or 21002, 21003, 21004)");
      console.error("  3. Start the blockchain:");
      console.error("     cd ../.. && docker-compose up -d");
    }
    
    console.error("\n" + "=".repeat(60));
    return false;
  }
}

// Run test
testConnection()
  .then(success => {
    process.exit(success ? 0 : 1);
  })
  .catch(error => {
    console.error("Unexpected error:", error);
    process.exit(1);
  });

