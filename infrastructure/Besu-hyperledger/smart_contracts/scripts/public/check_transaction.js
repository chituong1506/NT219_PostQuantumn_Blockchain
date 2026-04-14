const ethers = require('ethers');

// RPC endpoint
const host = process.env.RPC_ENDPOINT || "http://127.0.0.1:21001";

// Conversion rates
const WEI_TO_ETH = BigInt(10 ** 18);
const ETH_TO_VND_RATE = 1000000; // 1 ETH = 1,000,000 VND

function weiToVnd(wei) {
  const ethValue = Number(wei) / Number(WEI_TO_ETH);
  return Math.floor(ethValue * ETH_TO_VND_RATE);
}

function formatAddress(address) {
  if (!address) return 'N/A';
  return `${address.substring(0, 6)}...${address.substring(address.length - 4)}`;
}

async function checkTransaction(txHash) {
  try {
    const provider = new ethers.JsonRpcProvider(host);
    
    console.log('🔍 Checking transaction...\n');
    console.log(`Transaction Hash: ${txHash}\n`);
    console.log('='.repeat(80));
    
    // Get transaction
    const tx = await provider.getTransaction(txHash);
    if (!tx) {
      console.log('❌ Transaction not found!');
      return;
    }
    
    console.log('\n📋 Transaction Details:');
    console.log(`   From: ${tx.from}`);
    console.log(`   To: ${tx.to || 'Contract Creation'}`);
    console.log(`   Value: ${ethers.formatEther(tx.value)} ETH (${weiToVnd(tx.value).toLocaleString('vi-VN')} VND)`);
    console.log(`   Gas Limit: ${tx.gasLimit.toString()}`);
    const gasPriceWei = tx.gasPrice || 0n;
    const gasPriceGwei = typeof gasPriceWei === 'bigint' ? Number(gasPriceWei) / 1e9 : 0;
    console.log(`   Gas Price: ${gasPriceGwei.toFixed(2)} Gwei`);
    console.log(`   Nonce: ${tx.nonce}`);
    console.log(`   Block Number: ${tx.blockNumber || 'Pending'}`);
    console.log(`   Block Hash: ${tx.blockHash || 'Pending'}`);
    console.log(`   Transaction Index: ${tx.index !== null ? tx.index : 'Pending'}`);
    
    // Get receipt
    const receipt = await provider.getTransactionReceipt(txHash);
    if (receipt) {
      console.log('\n✅ Transaction Receipt:');
      console.log(`   Status: ${receipt.status === 1 ? '✅ Success' : '❌ Failed'}`);
      console.log(`   Block Number: ${receipt.blockNumber}`);
      console.log(`   Block Hash: ${receipt.blockHash}`);
      console.log(`   Transaction Index: ${receipt.index}`);
      console.log(`   Gas Used: ${receipt.gasUsed.toString()} (${(Number(receipt.gasUsed) / Number(tx.gasLimit) * 100).toFixed(2)}% of limit)`);
      console.log(`   Cumulative Gas Used: ${receipt.cumulativeGasUsed.toString()}`);
      const effectiveGasPriceWei = receipt.gasPrice || 0n;
      const effectiveGasPriceGwei = typeof effectiveGasPriceWei === 'bigint' ? Number(effectiveGasPriceWei) / 1e9 : 0;
      console.log(`   Effective Gas Price: ${effectiveGasPriceGwei.toFixed(2)} Gwei`);
      const feeWei = receipt.gasUsed * (receipt.gasPrice || 0n);
      console.log(`   Transaction Fee: ${ethers.formatEther(feeWei.toString())} ETH`);
      console.log(`   Logs Count: ${receipt.logs.length}`);
      
      // Get block info
      if (receipt.blockNumber) {
        const block = await provider.getBlock(receipt.blockNumber);
        if (block) {
          console.log('\n📦 Block Details:');
          console.log(`   Block Number: ${block.number}`);
          console.log(`   Block Hash: ${block.hash}`);
          console.log(`   Timestamp: ${new Date(Number(block.timestamp) * 1000).toLocaleString('vi-VN')}`);
          console.log(`   Transactions Count: ${block.transactions.length}`);
          console.log(`   Gas Used: ${block.gasUsed.toString()}`);
          console.log(`   Gas Limit: ${block.gasLimit.toString()}`);
        }
      }
      
      // Check if it's a contract interaction
      if (receipt.to && receipt.to.toLowerCase() !== '0x0000000000000000000000000000000000000000') {
        console.log('\n🔗 Contract Interaction:');
        console.log(`   Contract Address: ${receipt.to}`);
        
        // Try to decode logs if it's our InterbankTransfer contract
        if (receipt.logs.length > 0) {
          console.log(`   Events Emitted: ${receipt.logs.length}`);
          
          // Load contract ABI if available
          try {
            const path = require('path');
            const fs = require('fs-extra');
            const contractJsonPath = path.resolve(__dirname, '../../', 'contracts', 'InterbankTransfer.json');
            if (fs.existsSync(contractJsonPath)) {
              const contractJson = JSON.parse(fs.readFileSync(contractJsonPath));
              const contractAbi = contractJson.abi;
              const contract = new ethers.Contract(receipt.to, contractAbi, provider);
              
              console.log('\n📢 Decoded Events:');
              for (let i = 0; i < receipt.logs.length; i++) {
                const log = receipt.logs[i];
                try {
                  const parsedLog = contract.interface.parseLog(log);
                  if (parsedLog) {
                    console.log(`\n   Event ${i + 1}: ${parsedLog.name}`);
                    parsedLog.args.forEach((arg, index) => {
                      const name = parsedLog.fragment.inputs[index]?.name || `arg${index}`;
                      if (typeof arg === 'bigint') {
                        // Check if it's an address or amount
                        if (arg.toString().length === 66 || arg.toString().length === 42) {
                          // Probably an address or hash
                          try {
                            const addr = ethers.getAddress('0x' + arg.toString(16).padStart(40, '0'));
                            console.log(`      ${name}: ${addr}`);
                          } catch {
                            console.log(`      ${name}: ${arg.toString()}`);
                          }
                        } else {
                          // Probably an amount
                          const vnd = weiToVnd(arg);
                          console.log(`      ${name}: ${ethers.formatEther(arg)} ETH (${vnd.toLocaleString('vi-VN')} VND)`);
                        }
                      } else if (typeof arg === 'string' && arg.startsWith('0x')) {
                        try {
                          const addr = ethers.getAddress(arg);
                          console.log(`      ${name}: ${addr}`);
                        } catch {
                          console.log(`      ${name}: ${arg}`);
                        }
                      } else {
                        console.log(`      ${name}: ${arg}`);
                      }
                    });
                  }
                } catch (e) {
                  console.log(`   Event ${i + 1}: Unknown or not from InterbankTransfer contract`);
                }
              }
            }
          } catch (e) {
            // Contract ABI not found, skip decoding
          }
        }
      }
    } else {
      console.log('\n⏳ Transaction Status: Pending (not yet included in a block)');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n💡 Tips:');
    console.log('   - Transaction hash: Use to search on blockchain explorer');
    console.log('   - Block number: Transaction was included in this block');
    console.log('   - Gas used: Amount of computation resources consumed');
    console.log('   - Status: 1 = Success, 0 = Failed');
    
  } catch (error) {
    console.error('❌ Error checking transaction:', error.message);
    if (error.code === 'CALL_EXCEPTION' || error.message.includes('not found')) {
      console.error('\n💡 Transaction might not exist or is still pending.');
    }
  }
}

// Get transaction hash from command line
const txHash = process.argv[2];

if (!txHash) {
  console.log('Usage: node check_transaction.js <transaction_hash>');
  console.log('\nExample:');
  console.log('  node check_transaction.js 0x484f14a9aa940a48f9bca268050485811179d8b0cf68aeed8f83aceeb4aa2283');
  process.exit(1);
}

checkTransaction(txHash)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error:', error);
    process.exit(1);
  });

