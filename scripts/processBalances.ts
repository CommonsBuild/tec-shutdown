import { readFileSync, writeFileSync } from 'fs';

interface BalanceRow {
  address: string;
  before: string;
  after: string;
}

interface ProcessedRow extends BalanceRow {
  min: string;
  diff: string;
}

async function main() {
  console.log('📖 Reading tec_balances.csv...');
  
  // Read CSV file
  const csvContent = readFileSync('tec_balances.csv', 'utf-8');
  const lines = csvContent.split('\n');
  
  // Skip header
  const header = lines[0];
  const dataLines = lines.slice(1);
  
  console.log(`✨ Found ${dataLines.length} total rows`);
  
  // Parse and filter rows
  const processedRows: ProcessedRow[] = [];
  
  for (const line of dataLines) {
    if (!line.trim()) continue;
    
    const parts = line.split(',');
    if (parts.length < 3) continue;
    
    const address = parts[0].trim();
    const before = parts[1].trim();
    const after = parts[2].trim();
    
    // Skip rows where before === after
    if (before === after) {
      continue;
    }
    
    // Calculate min and diff
    const beforeBigInt = BigInt(before);
    const afterBigInt = BigInt(after);
    const minBigInt = beforeBigInt < afterBigInt ? beforeBigInt : afterBigInt;
    const diffBigInt = afterBigInt - minBigInt;
    
    processedRows.push({
      address,
      before,
      after,
      min: minBigInt.toString(),
      diff: diffBigInt.toString(),
    });
  }
  
  console.log(`✅ Filtered to ${processedRows.length} rows with changes`);
  
  // Create CSV with new columns
  console.log('📝 Creating CSV file...');
  
  const csvLines = ['address,before,after,min,diff'];
  for (const row of processedRows) {
    csvLines.push(`${row.address},${row.before},${row.after},${row.min},${row.diff}`);
  }
  
  const outputContent = csvLines.join('\n');
  const filename = 'tec_balances_changes.csv';
  
  writeFileSync(filename, outputContent);
  
  console.log(`\n✅ Done! Saved ${processedRows.length} changed balances to ${filename}`);
}

main().catch(console.error);

