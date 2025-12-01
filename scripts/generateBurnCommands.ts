import { readFileSync, writeFileSync } from 'fs';

function main() {
  console.log('📖 Reading tec_balances_changes.csv...');
  const csvContent = readFileSync('tec_balances_changes.csv', 'utf-8');
  const lines = csvContent.split('\n').slice(1); // Skip header

  const burnCommands: string[] = [];

  for (const line of lines) {
    if (!line.trim()) continue;
    const parts = line.split(',');
    if (parts.length < 5) continue;

    const address = parts[0].trim();
    const diff = parts[4].trim();

    // Only process if diff is not 0
    if (diff !== '0' && diff !== '') {
      burnCommands.push(`exec $spender burn(address,uint) ${address} ${diff} --from $giveth`);
    }
  }

  console.log(`✨ Found ${burnCommands.length} addresses with non-zero diff`);

  // Write to output file
  const outputContent = burnCommands.join('\n') + '\n';
  const filename = 'burn_commands.txt';

  writeFileSync(filename, outputContent);

  console.log(`\n✅ Done! Saved ${burnCommands.length} burn commands to ${filename}`);
}

main();

