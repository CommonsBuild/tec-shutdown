import { createPublicClient, http, parseAbiItem } from 'viem';
import { optimism } from 'viem/chains';
import { writeFileSync } from 'fs';

// TokenManager address from optimism.json
const TOKEN_MANAGER_ADDRESS = '0x19b5b7887216ae05db3921b87d875e2ccdb7ae2c' as const;

// ABI for the token() function on TokenManager
const TOKEN_MANAGER_ABI = [
  {
    type: 'function',
    name: 'token',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'address' }],
  },
] as const;

async function main() {
  console.log('🔗 Connecting to Optimism mainnet...');
  
  // Use the same RPC as defined in hardhat.config.ts
  const rpcUrl = `https://lb.drpc.live/optimism/${process.env.OPTIMISM_DRPC_API_KEY}`;
  
  const client = createPublicClient({
    chain: optimism,
    transport: http(rpcUrl),
  });

  // Get TEC token address from TokenManager
  console.log('📍 Fetching TEC token address from TokenManager...');
  const tecTokenAddress = await client.readContract({
    address: TOKEN_MANAGER_ADDRESS,
    abi: TOKEN_MANAGER_ABI,
    functionName: 'token',
  });

  console.log(`✅ TEC Token address: ${tecTokenAddress}`);

  // Block range to fetch transfers from
  const BLOCK_BEFORE = 138850000n;
  const BLOCK_AFTER = 144895034n;
  
  console.log(`📦 Fetching transfers from block ${BLOCK_BEFORE} to ${BLOCK_AFTER}`);

  // Fetch all Transfer events
  // Transfer event signature: Transfer(address indexed from, address indexed to, uint256 value)
  console.log('🔍 Fetching all Transfer events (this may take a while)...');
  
  const transferEvent = parseAbiItem('event Transfer(address indexed from, address indexed to, uint256 value)');
  
  // We'll fetch in chunks to avoid RPC limits
  const CHUNK_SIZE = 10000n;
  
  let allTransfers: any[] = [];
  let currentChunkStart = BLOCK_BEFORE;
  
  while (currentChunkStart < BLOCK_AFTER) {
    const toBlock = currentChunkStart + CHUNK_SIZE > BLOCK_AFTER 
      ? BLOCK_AFTER 
      : currentChunkStart + CHUNK_SIZE;
    
    console.log(`  Fetching blocks ${currentChunkStart} to ${toBlock}...`);
    
    try {
      const logs = await client.getLogs({
        address: tecTokenAddress,
        event: transferEvent,
        fromBlock: currentChunkStart,
        toBlock: toBlock,
      });
      
      allTransfers = allTransfers.concat(logs);
      console.log(`  Found ${logs.length} transfers (total so far: ${allTransfers.length})`);
    } catch (error) {
      console.error(`  Error fetching blocks ${currentChunkStart}-${toBlock}:`, error);
      // Try with smaller chunk size if we hit rate limits
      if (CHUNK_SIZE > 1000n) {
        console.log('  Retrying with smaller chunk size...');
        continue;
      }
    }
    
    currentChunkStart = toBlock + 1n;
  }

  console.log(`\n✨ Total transfers found: ${allTransfers.length}`);

  // Create CSV with transaction hash, from address, and to address
  console.log('📝 Creating CSV file...');
  
  const csvLines = ['transaction_hash,from_address,to_address'];
  
  for (const transfer of allTransfers) {
    const fromAddress = transfer.args?.from || '';
    const toAddress = transfer.args?.to || '';
    csvLines.push(`${transfer.transactionHash},${fromAddress},${toAddress}`);
  }
  
  const csvContent = csvLines.join('\n');
  const filename = 'tec_transfers.csv';
  
  writeFileSync(filename, csvContent);
  
  console.log(`\n✅ Done! Saved ${allTransfers.length} transfers to ${filename}`);
  console.log(`\nTEC Token: ${tecTokenAddress}`);
  console.log(`Total transfers: ${allTransfers.length}`);
}

main().catch(console.error);

