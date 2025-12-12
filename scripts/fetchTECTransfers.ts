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
  // Common RPC log limits: 10000 (Alchemy), 10000 (Infura), varies by provider
  const RPC_LOG_LIMIT = 10000;
  const MIN_CHUNK_SIZE = 100n;
  const INITIAL_CHUNK_SIZE = 10000n;
  
  let allTransfers: any[] = [];
  let currentChunkStart = BLOCK_BEFORE;
  let chunkSize = INITIAL_CHUNK_SIZE;
  
  while (currentChunkStart <= BLOCK_AFTER) {
    const toBlock = currentChunkStart + chunkSize > BLOCK_AFTER 
      ? BLOCK_AFTER 
      : currentChunkStart + chunkSize;
    
    console.log(`  Fetching blocks ${currentChunkStart} to ${toBlock} (chunk size: ${chunkSize})...`);
    
    try {
      const logs = await client.getLogs({
        address: tecTokenAddress,
        event: transferEvent,
        fromBlock: currentChunkStart,
        toBlock: toBlock,
      });
      
      // Check for potential truncation: if we hit exactly the RPC limit,
      // the response was likely truncated
      if (logs.length >= RPC_LOG_LIMIT) {
        console.log(`  ⚠️  Got ${logs.length} logs (at RPC limit) - likely truncated!`);
        
        if (chunkSize > MIN_CHUNK_SIZE) {
          // Reduce chunk size and retry this range
          chunkSize = chunkSize / 2n;
          console.log(`  Reducing chunk size to ${chunkSize} and retrying...`);
          continue;
        } else {
          // Can't reduce further - warn but continue
          console.warn(`  ⚠️  WARNING: Chunk size at minimum but still hitting limit!`);
          console.warn(`  ⚠️  Blocks ${currentChunkStart}-${toBlock} may have missing transfers!`);
        }
      }
      
      allTransfers = allTransfers.concat(logs);
      console.log(`  Found ${logs.length} transfers (total so far: ${allTransfers.length})`);
      
      // Successful fetch - try to gradually increase chunk size for efficiency
      if (logs.length < RPC_LOG_LIMIT / 2 && chunkSize < INITIAL_CHUNK_SIZE) {
        chunkSize = chunkSize * 2n > INITIAL_CHUNK_SIZE ? INITIAL_CHUNK_SIZE : chunkSize * 2n;
      }
      
    } catch (error) {
      console.error(`  Error fetching blocks ${currentChunkStart}-${toBlock}:`, error);
      
      if (chunkSize > MIN_CHUNK_SIZE) {
        // Reduce chunk size and retry
        chunkSize = chunkSize / 2n;
        console.log(`  Reducing chunk size to ${chunkSize} and retrying...`);
        continue;
      } else {
        // Can't reduce further - this is a real problem
        throw new Error(`Failed to fetch blocks ${currentChunkStart}-${toBlock} even with minimum chunk size`);
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

