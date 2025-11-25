# TEC Shutdown - Token Claim Contract

This project contains the TECClaim smart contract, an upgradeable contract that allows Token Engineering Commons (TEC) token holders to claim their proportional share of treasury assets during the shutdown process.

## Project Overview

The TECClaim contract enables TEC token holders to burn their tokens in exchange for a proportional share of redeemable tokens (DAI, RETH, etc.) held in the contract. The contract uses the UUPS upgradeable proxy pattern and includes features for address blocking and owner withdrawal after a deadline.

### Key Features

- **Proportional Claims**: Users can claim their proportional share of treasury assets based on their TEC token holdings
- **Token Burning**: TEC tokens are burned upon claiming to prevent double-claims
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

The test suite includes 19 comprehensive tests covering:

- ✅ **Basic Functionality**
  - Contract initialization
  - Proportional token distribution
  - Multiple users claiming
  - Event emissions

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

All 19 tests are passing ✅

## Project Structure

```
contracts/
├── TECClaim.sol       # Main claim contract (UUPS upgradeable)
└── TECClaim.t.sol     # Comprehensive test suite

ignition/
└── modules/           # Hardhat Ignition deployment modules
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

1. Deploy the implementation contract
2. Deploy the ERC1967Proxy with initialization data
3. Transfer redeemable tokens (DAI, RETH, etc.) to the proxy address
4. Set the claim deadline appropriately

Example deployment flow is demonstrated in the test suite setup.

## License

AGPL-3.0

## Additional Resources

- [Hardhat 3 Documentation](https://hardhat.org/docs/getting-started)
- [OpenZeppelin Upgradeable Contracts](https://docs.openzeppelin.com/contracts/4.x/upgradeable)
- [UUPS Proxy Pattern](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable)
