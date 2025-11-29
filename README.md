# TEC Shutdown - Token Claim Contract

This project contains the TECClaim smart contract, an upgradeable contract that allows Token Engineering Commons (TEC) token holders to claim their proportional share of treasury assets during the shutdown process.

## Project Overview

The TECClaim contract enables TEC token holders to burn their snapshot tokens in exchange for a proportional share of redeemable tokens (DAI, RETH, etc.) held in the contract. The contract uses the UUPS upgradeable proxy pattern and includes features for address blocking and owner withdrawal after a deadline.

The contract uses a **non-transferable snapshot** of the TEC token, created at deployment time using MiniMe's `createCloneToken` functionality. This snapshot is frozen at a specific block height and cannot be transferred, making it perfect for claim tracking.

### Key Features

- **Non-Transferable Snapshot**: Creates a frozen snapshot of TEC token balances at deployment
- **Proportional Claims**: Users can claim their proportional share of treasury assets based on their snapshot token holdings
- **Token Burning**: Snapshot tokens are burned upon claiming to prevent double-claims
- **MiniMe Token Integration**: Uses MiniMe's clone token functionality for secure snapshots
- **Blocklist**: Contract owner can block/unblock specific addresses from claiming
- **Deadline Mechanism**: After the claim deadline, the owner can withdraw any remaining unclaimed tokens
- **Upgradeable**: Uses UUPS proxy pattern for upgradeability
- **Multi-Token Support**: Can distribute multiple types of redeemable tokens (DAI, RETH, etc.)

## Contract Details

### TECClaim.sol

The main contract that handles the token claiming logic:

- `claim()` - Burns user's TEC tokens and transfers proportional share of redeemable tokens
- `claimRemaining()` - Owner can claim remaining tokens after deadline (owner only)
- `blockAddresses()` - Block addresses from claiming (owner only)
- `unblockAddresses()` - Unblock previously blocked addresses (owner only)

### Test Configuration

The test suite includes:
- **DAI**: 100,000 tokens loaded in the claim contract
- **RETH**: 16 tokens loaded in the claim contract
- **TEC**: Total supply of 1,136,450 tokens distributed among test users

## Testing

The project includes comprehensive Solidity tests written using Foundry-style testing with Hardhat.

### Running All Tests

```shell
bunx hardhat test
```

### Running Only TECClaim Tests

```shell
bunx hardhat test contracts/TECClaim.t.sol
```

### Test Coverage

The test suite includes 27 comprehensive tests covering:

- ✅ **Basic Functionality**
  - Contract initialization with snapshot token creation
  - Proportional token distribution
  - Multiple users claiming
  - Event emissions
  - Snapshot token burning

- ✅ **Error Cases**
  - Claiming with zero balance
  - Double claiming prevention
  - Blocked address restrictions

- ✅ **Blocklist Management**
  - Blocking addresses
  - Unblocking addresses
  - Access control (owner-only operations)

- ✅ **Deadline & Withdrawal**
  - Owner withdrawal after deadline
  - Preventing premature withdrawal
  - Remaining token calculations

- ✅ **Edge Cases**
  - Single redeemable token scenarios
  - Partial claims
  - Distribution accuracy

All 27 tests are passing ✅

## Project Structure

```
contracts/
├── TECClaim.sol          # Main claim contract (UUPS upgradeable)
├── TECClaimFactory.sol   # Factory for creating TECClaim proxies
└── TECClaim.t.sol        # Comprehensive test suite

ignition/
└── modules/              # Hardhat Ignition deployment modules
```

## Development

This project uses:
- **Hardhat 3** - Ethereum development environment
- **Solidity 0.8.28** - Smart contract language
- **OpenZeppelin Contracts** - Upgradeable contract libraries
- **Foundry-style Testing** - Using forge-std/Test.sol
- **Bun** - Fast JavaScript runtime (alternative to npm)

## Configuration

The contract is configured with:
- UUPS upgradeable proxy pattern
- Ownable access control
- SafeERC20 for secure token transfers
- Custom error messages for gas efficiency

## Deployment

To deploy the TECClaim contract, you'll need to:

1. Deploy the implementation contract (TECClaim)
2. Deploy the factory contract (TECClaimFactory) with the implementation address
3. Use the factory to create a proxy with initialization parameters
4. Transfer redeemable tokens (DAI, RETH, etc.) to the proxy address
5. Call `startClaim()` to activate claiming

Example deployment flow is demonstrated in the ignition module and test suite setup.

## License

AGPL-3.0

## Additional Resources

- [Hardhat 3 Documentation](https://hardhat.org/docs/getting-started)
- [OpenZeppelin Upgradeable Contracts](https://docs.openzeppelin.com/contracts/4.x/upgradeable)
- [UUPS Proxy Pattern](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
