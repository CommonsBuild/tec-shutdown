import { readFileSync, writeFileSync } from 'fs';

function main() {
  console.log('📖 Reading tec_balances_changes.csv...');
  const csvContent = readFileSync('tec_balances_changes.csv', 'utf-8');
  const lines = csvContent.split('\n').slice(1); // Skip header

  const burnCommands: string[] = [];
  let totalBurned = 0n;

  for (const line of lines) {
    if (!line.trim()) continue;
    const parts = line.split(',');
    if (parts.length < 5) continue;

    const address = parts[0].trim();
    const diff = parts[4].trim();

    // Only process if diff is not 0
    if (diff !== '0' && diff !== '') {
      burnCommands.push(`exec $spender burn(address,uint) ${address} ${diff}`);
      totalBurned += BigInt(diff);
    }
  }

  console.log(`✨ Found ${burnCommands.length} addresses with non-zero diff`);

  // Write to output file
  const outputContent = 'set $spender 0x873f0EFeA1a72B2a5ff6ef755fF5Cbf80A324D43\n' + burnCommands.join('\n') + '\n';
  const filename = 'tec_burn_commands.txt';

  writeFileSync(filename, outputContent);

  console.log(`\n✅ Done! Saved ${burnCommands.length} burn commands to ${filename}`);
  console.log(`🔥 Total TEC to burn: ${(Number(totalBurned) / 1e18).toFixed(4)} TEC`);
}

main();



