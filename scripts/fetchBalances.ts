import { createPublicClient, http } from 'viem';
import { optimism } from 'viem/chains';
import { readFileSync, writeFileSync } from 'fs';

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

// ABI for balanceOfAt on MiniMe token
const BALANCEOF_AT_ABI = [
  {
    type: 'function',
    name: 'balanceOfAt',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'blockNumber', type: 'uint256' },
    ],
    outputs: [{ type: 'uint256' }],
  },
] as const;

const BLOCK_BEFORE = 138850000n;
const BLOCK_AFTER = 144200000n;

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

  // Read CSV file
  console.log('📖 Reading tec_transfers.csv...');
  const csvContent = readFileSync('tec_transfers.csv', 'utf-8');
  const lines = csvContent.split('\n').slice(1); // Skip header
  
  // Extract unique addresses
  const uniqueAddresses = new Set<string>();
  for (const line of lines) {
    if (!line.trim()) continue;
    const parts = line.split(',');
    if (parts.length >= 2) {
      const address = parts[1].trim();
      if (address && address.startsWith('0x')) {
        uniqueAddresses.add(address);
      }
    }
  }

  console.log(`✨ Found ${uniqueAddresses.size} unique addresses`);

  // Fetch balances for each address
  console.log(`🔍 Fetching balances at blocks ${BLOCK_BEFORE} and ${BLOCK_AFTER}...`);
  
  const results: Array<{ address: string; before: string; after: string }> = [];
  const addressArray = Array.from(uniqueAddresses);
  
  let processed = 0;
  for (const address of addressArray) {
    try {
      const [balanceBefore, balanceAfter] = await Promise.all([
        client.readContract({
          address: tecTokenAddress,
          abi: BALANCEOF_AT_ABI,
          functionName: 'balanceOfAt',
          args: [address as `0x${string}`, BLOCK_BEFORE],
        }),
        client.readContract({
          address: tecTokenAddress,
          abi: BALANCEOF_AT_ABI,
          functionName: 'balanceOfAt',
          args: [address as `0x${string}`, BLOCK_AFTER],
        }),
      ]);

      results.push({
        address,
        before: balanceBefore.toString(),
        after: balanceAfter.toString(),
      });

      processed++;
      if (processed % 100 === 0) {
        console.log(`  Processed ${processed}/${addressArray.length} addresses...`);
      }
    } catch (error) {
      console.error(`  Error fetching balance for ${address}:`, error);
      // Continue with other addresses
    }
  }

  console.log(`\n✅ Successfully fetched balances for ${results.length} addresses`);

  // Create CSV
  console.log('📝 Creating CSV file...');
  
  const csvLines = ['address,before,after'];
  for (const result of results) {
    csvLines.push(`${result.address},${result.before},${result.after}`);
  }
  
  const outputContent = csvLines.join('\n');
  const filename = 'tec_balances.csv';
  
  writeFileSync(filename, outputContent);
  
  console.log(`\n✅ Done! Saved balances for ${results.length} addresses to ${filename}`);
}

main().catch(console.error);

