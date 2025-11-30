# TECClaim Deployment Guide

This guide provides step-by-step instructions for deploying the TECClaim contract using Hardhat Ignition.

## Prerequisites

Before deploying, ensure you have:

1. **Required Contract Addresses:**
   - TEC MiniMe Token address (the source token to create a snapshot from)
   - DAI token address
   - RETH token address (or other redeemable tokens)

3. **Deployment Parameters:**
   - Claim deadline (Unix timestamp in seconds)
   - Owner address (who will control the contract)

4. **Funded Account:**
   - Private key with sufficient ETH for gas fees
   - Recommended: 0.01 ETH for Optimism, more for Ethereum mainnet

## Architecture Overview

The TECClaim contract uses the **UUPS (Universal Upgradeable Proxy Standard)** pattern with a factory for deployment:

```
┌─────────────────────────────────────┐
│   TECClaimFactory                    │
│  (contracts/TECClaimFactory.sol)     │
│  - Deploys ERC1967Proxy instances    │
│  - Configured with implementation    │
│  - Simplifies deployment             │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│         Proxy Contract               │
│  (ERC1967Proxy)                      │
│  - Stores contract state             │
│  - Delegates calls to implementation │
│  - Created by TECClaimFactory        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   TECClaim Implementation            │
│  (contracts/TECClaim.sol)            │
│  - Contains business logic           │
│  - Upgradeable by owner              │
│  - UUPS upgrade mechanism            │
│  - Creates snapshot token on init    │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Non-Transferable Snapshot Token   │
│  - Created via createCloneToken()    │
│  - Frozen at snapshot block          │
│  - Transfers disabled                │
│  - TECClaim is controller            │
│  - Created after proxy initialization│
└─────────────────────────────────────┘
```

**Key Points:**
- Users always interact with the **Proxy address**
- The Proxy delegates all calls to the Implementation
- State is stored in the Proxy, not the Implementation
- Owner can upgrade to new Implementation via UUPS pattern
- The Implementation address can change, but Proxy address stays constant
- **TECClaimFactory simplifies proxy creation** by encapsulating initialization
- **A non-transferable snapshot is created via `createSnapshotToken()`** after initialization
- The snapshot is frozen at the block when `createSnapshotToken()` is called
- Owner can adjust snapshot balances with `burn()` before activating claims

## Contract State Machine

The TECClaim contract uses a state machine to manage the claim lifecycle:

```
┌──────────┐
│ dormant  │  (initial state, never used in practice)
└──────────┘
     │
     ▼
┌────────────┐
│ configured │  After initialize() is called
└──────────┬─┘  - Contract is set up with parameters
           │    - Parent token reference stored
           │    - Redeemable tokens configured
           │    - Snapshot token NOT yet created
           │    - Cannot claim yet
           │
           │ createSnapshotToken() called by owner
           │ (creates non-transferable snapshot at current block)
           │
           │ [Optional: burn() to adjust specific balances]
           │
           │ startClaim() called by owner
           │ (transfers tokens to contract)
           ▼
┌──────────┐
│  active  │  Users can claim their tokens
└──────────┬─┘  - claim() function is enabled
           │    - Users burn snapshot tokens to receive redeemables
           │    - Owner can block/unblock addresses
           │
           │ claimRemaining() called after deadline
           │
           ▼
┌────────────┐
│ finialized │  Claim period ended
└────────────┘  - Owner claimed remaining tokens
                - No more claims possible
```

**State Transitions:**
1. **dormant → configured**: Happens during `initialize()` (deployment)
2. **Within configured**: Owner calls `createSnapshotToken()` to create the snapshot, optionally calls `burn()` to adjust balances
3. **configured → active**: Owner calls `startClaim()` to transfer redeemable tokens and enable claiming
4. **active → finialized**: Owner calls `claimRemaining()` after deadline to collect unclaimed tokens

**Important**: The `startClaim()` function must be called by the owner after deployment to activate claiming. This allows the owner to coordinate the transfer of redeemable tokens from multiple sources before users can start claiming.

## Local Deployment (Testing with Forked Optimism)

The local deployment uses a forked Optimism network, allowing you to test with real Optimism mainnet state.

### Step 1: Start Local Forked Node

The configuration in `hardhat.config.ts` includes a `local` network that forks Optimism:

```bash
# In terminal 1
npx hardhat node --network local
```

This will start a local node on `http://127.0.0.1:8545` with forked Optimism state.

### Step 2: Update Parameters

Edit `ignition/parameters/local.json` with your deployment parameters. Example:

```json
{
  "TECClaimModule": {
    "tecTokenAddress": "0x8fc7c1109c08904160d6ae36482b79814d45eb78",
    "daiAddress": "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
    "rethAddress": "0x9Bcef72be871e61ED4fBbc7630889beE758eb81D",
    "claimDeadline": "1779726356",
    "ownerAddress": "0x4D9339dd97db55e3B9bCBE65dE39fF9c04d1C2cd"
  }
}
```

**Important Notes:**
- `tecTokenAddress`: The source MiniMe token address to create a snapshot from
- A non-transferable snapshot will be created when `createSnapshotToken()` is called
- The snapshot will be frozen at the block when `createSnapshotToken()` is called

### Step 3: Compile Contracts

```bash
npx hardhat compile
```

This generates artifacts for TECClaim and TECClaimFactory.

### Step 4: Deploy TECClaim

In a new terminal:

```bash
npx hardhat ignition deploy ignition/modules/TECClaim.ts \
  --parameters ignition/parameters/local.json \
  --network localhost
```

Expected output:

```
Hardhat Ignition 🚀

Deploying [ TECClaimModule ]

Batch #1
  Executed TECClaimModule#TECClaim_Implementation

Batch #2
  Executed TECClaimModule#TECClaimFactory

Batch #3
  Executed TECClaimModule#TECClaim_Proxy_Creation

Batch #4
  Executed TECClaimModule#TECClaim_CreateSnapshot

Batch #5
  Executed TECClaimModule#TECClaim

[ TECClaimModule ] successfully deployed 🚀

Deployed Addresses

TECClaimModule#TECClaim_Implementation - 0x...
TECClaimModule#TECClaimFactory - 0x...
TECClaimModule#TECClaim_Proxy_Creation - 0x... (proxy address)
TECClaimModule#TECClaim - 0x... (proxy address)
```

### Step 5: Optionally Adjust Snapshot Balances

If you need to burn specific addresses' snapshot tokens before activation (e.g., to exclude certain accounts):

```bash
# Using cast (Foundry)
cast send $PROXY_ADDRESS "burn(address,uint256)" $ADDRESS_TO_BURN $AMOUNT \
  --rpc-url http://127.0.0.1:8545 \
  --private-key $OWNER_KEY
```

This step is optional and should only be done if needed before activating claims.

### Step 6: Fund the Contract and Start Claiming

After deployment, the contract is in the `configured` state. You need to transfer redeemable tokens and activate claiming:

**Option A: Manual Transfer + startClaim()**

**Option A: Manual Transfer + startClaim()**

If you want to use `startClaim()` to pull tokens from multiple sources:

```bash
# First, identify addresses that hold the redeemable tokens
# For example: DAO treasury, multisig wallets, etc.

# Then call startClaim with those addresses
# This requires those addresses to have approved the contract first
# The function will automatically pull all redeemableTokens from the specified addresses
```

**Option B: Direct Transfer (Simple)**

You can also simply transfer tokens directly to the contract and then call `startClaim()` with an empty array:

```solidity
// Transfer tokens to contract address
dai.transfer(proxyAddress, DAI_AMOUNT);
reth.transfer(proxyAddress, RETH_AMOUNT);

// Activate claiming (with empty array since tokens are already in contract)
claim.startClaim([]);
```

Since you're using a forked network, you can impersonate accounts that hold these tokens.

**Verify State Transition:**

```bash
# Check state (should be 2 for "active")
cast call $PROXY_ADDRESS "state()(uint8)" --rpc-url http://127.0.0.1:8545
```

## Optimism Mainnet Deployment

### Step 1: Verify Configuration

The `hardhat.config.ts` already includes Optimism network configuration:

```typescript
optimism: {
  type: "http",
  url: "https://lb.drpc.live/optimism/...",  // Your RPC URL
  chainId: 10,
}
```

For production deployment, update with your own RPC URL (from Infura, Alchemy, or other providers).

### Step 2: Configure Private Key

Store your deployer private key securely:

```bash
npx hardhat keystore set OPTIMISM_PRIVATE_KEY
# Enter your private key (without 0x prefix)
```

Update `hardhat.config.ts` to use it:

```typescript
optimism: {
  type: "http",
  url: "https://mainnet.optimism.io",
  chainId: 10,
  accounts: [configVariable("OPTIMISM_PRIVATE_KEY")],
}
```

### Step 3: Update Parameters

The `ignition/parameters/optimism.json` file contains deployment parameters:

```json
{
  "TECClaimModule": {
    "tecTokenAddress": "0x8fc7c1109c08904160d6ae36482b79814d45eb78",
    "daiAddress": "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
    "rethAddress": "0x9Bcef72be871e61ED4fBbc7630889beE758eb81D",
    "claimDeadline": "1779726356",
    "ownerAddress": "0x4D9339dd97db55e3B9bCBE65dE39fF9c04d1C2cd"
  }
}
```

**Important**: Verify these addresses:
- TEC Token (MiniMe): The source TEC token address on Optimism to create snapshot from
- DAI: `0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1` (Optimism DAI)
- RETH: `0x9Bcef72be871e61ED4fBbc7630889beE758eb81D` (Optimism RETH)

### Step 4: Compile Contracts

```bash
npx hardhat compile
```

### Step 5: Deploy to Optimism

```bash
npx hardhat ignition deploy ignition/modules/TECClaim.ts \
  --network optimism \
  --parameters ignition/parameters/optimism.json
```

### Step 6: Verify Contract

After deployment, verify on Optimistic Etherscan:

```bash
npx hardhat ignition verify <deployment-id>
```

The deployment ID will be shown after successful deployment. Verification will make the contract readable on https://optimistic.etherscan.io

### Step 7: Fund the Contract and Activate Claims

After deployment, the contract is in the `configured` state. You must activate it before users can claim:

**Step 7a: Transfer Redeemable Tokens**

Transfer the required amounts of redeemable tokens to the proxy address:

```bash
# Option 1: If tokens are in a single address
# Simply transfer to the proxy address using your wallet or Optimistic Etherscan

# Option 2: If tokens are spread across multiple addresses
# Prepare those addresses to approve the contract
```

**Step 7b: Call startClaim() to Activate**

The owner must call `startClaim()` to transition from `configured` to `active` state:

```solidity
// If tokens are already in the contract (transferred manually):
claim.startClaim([]);

// If tokens need to be pulled from multiple addresses:
address[] memory holders = [treasuryAddress, multisigAddress];
claim.startClaim(holders);
// Note: holders must approve the contract first
// The function will pull all redeemableTokens from the specified holders
```

Using cast (Foundry):
```bash
# If tokens already transferred to contract:
cast send $PROXY_ADDRESS "startClaim(address[])" "[]" \
  --rpc-url $OPTIMISM_RPC \
  --private-key $OWNER_KEY

# To pull from multiple sources (example with 2 addresses):
cast send $PROXY_ADDRESS "startClaim(address[])" \
  "[$TREASURY_ADDRESS,$MULTISIG_ADDRESS]" \
  --rpc-url $OPTIMISM_RPC \
  --private-key $OWNER_KEY
```

**Step 7c: Verify State**

```bash
# Check state (should return 2 for "active")
cast call $PROXY_ADDRESS "state()(uint8)" --rpc-url $OPTIMISM_RPC
```

## Production Deployment Checklist

⚠️ **CRITICAL**: Before deploying to Optimism mainnet:

### Pre-Deployment Review

1. **Test Thoroughly**
   - Deploy and test on local forked network
   - Test all claim scenarios
   - Test state transitions (configured → active → finialized)
   - Test `createSnapshotToken()` function
   - Test `burn()` function for snapshot adjustments
   - Test `startClaim()` function with various scenarios
   - Verify snapshot token creation timing
   - Test blocklist functionality
   - Test owner functions
   - Confirm deadline mechanism works
   - Test claiming before `startClaim()` is called (should revert)

2. **Verify All Parameters**
   - [ ] TEC Token (MiniMe) source address is correct for Optimism
   - [ ] DAI address: `0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1`
   - [ ] RETH address: `0x9Bcef72be871e61ED4fBbc7630889beE758eb81D`
   - [ ] Claim deadline is set correctly (Unix timestamp)
   - [ ] Owner address is secure (recommend Gnosis Safe multisig)

3. **Security Considerations**
   - [ ] Owner is a multisig wallet (recommended)
   - [ ] Private key for deployment is secure
   - [ ] Sufficient ETH in deployer account (~0.01 ETH for gas)
   - [ ] Contract has been audited (recommended for production)

4. **Prepare Token Transfers**
   - [ ] Calculate exact token amounts to transfer
   - [ ] Prepare DAI transfer transaction
   - [ ] Prepare RETH transfer transaction
   - [ ] Have token approvals ready if using multisig
   - [ ] Decide strategy for `startClaim()`: direct transfer or pull from multiple sources

### Deployment Steps

1. Compile contracts: `npx hardhat compile`
2. Deploy to Optimism: `npx hardhat ignition deploy ignition/modules/TECClaim.ts --network optimism --parameters ignition/parameters/optimism.json`
3. Save deployment addresses (especially proxy address)
4. Verify on Optimistic Etherscan: `npx hardhat ignition verify <deployment-id>`
5. Verify contract is in `configured` state (state should be 1)
6. **Verify snapshot token was created** (`token()` should return non-zero address)
7. **(Optional) Call `burn()` to adjust specific addresses' snapshot balances if needed**
8. **Set TECClaim as controller of the snapshot token** (already done automatically by `createSnapshotToken()`)
9. Transfer redeemable tokens to proxy address OR prepare approval if using `startClaim()` to pull tokens
10. **Call `startClaim()` from owner address to activate claiming**
11. Verify contract is in `active` state (state should be 2)
12. Verify TECClaim is the controller of the snapshot token
13. Test with small claim (if possible)

## Post-Deployment Checklist

After deployment, verify:

- [ ] Contract is verified on Optimistic Etherscan
- [ ] Owner address is correct (`owner()` view function)
- [ ] Claim deadline is set correctly (`claimDeadline()` view function)
- [ ] Source TEC Token address is correct (`parentToken()` view function)
- [ ] Snapshot token was created successfully (`token()` returns non-zero address)
- [ ] Snapshot token is non-transferable (verify `transfersEnabled()` returns false on snapshot)
- [ ] Redeemable tokens array is correct
- [ ] Contract state is `configured` (1) after deployment and snapshot creation
- [ ] All redeemable tokens are transferred to proxy contract
- [ ] **`startClaim()` has been called by owner**
- [ ] **Contract state is now `active` (2)**
- [ ] Test claim with small amount (if possible)
- [ ] Document deployment addresses in secure location
- [ ] Update frontend/UI with new proxy contract address
- [ ] Set up monitoring for contract events (especially state transitions)
- [ ] Save deployment ID for future reference

## Contract Functions Reference

### State Management Functions

**`createSnapshotToken()`** - Owner only
- **Purpose**: Creates a non-transferable snapshot of the parent TEC token
- **When to use**: After deployment, before activating claims
- **Requirements**:
  - Must be called by owner
  - Contract must be in `configured` state
  - Can only be called once (snapshot creation is permanent)
- **Effects**: Creates a MiniMe clone token with transfers disabled, frozen at current block
- **State**: Remains in `configured` state after execution

**`burn(address _owner, uint256 _amount)`** - Owner only
- **Purpose**: Burns snapshot tokens from a specific address before activation
- **When to use**: After creating snapshot but before calling `startClaim()`, if you need to exclude or adjust balances
- **Parameters**:
  - `_owner`: Address to burn tokens from
  - `_amount`: Amount of snapshot tokens to burn
- **Requirements**:
  - Must be called by owner
  - Contract must be in `configured` state
  - Snapshot token must already exist (call `createSnapshotToken()` first)
- **Effects**: Reduces the snapshot token balance of the specified address
- **State**: Remains in `configured` state after execution

**`startClaim(address[] from)`** - Owner only
- **Purpose**: Activates the claim contract by transitioning from `configured` to `active` state
- **When to use**: After deployment and funding the contract with redeemable tokens
- **Parameters**:
  - `from`: Array of addresses to pull tokens from (can be empty if already funded)
- **Requirements**:
  - Must be called by owner
  - Contract must be in `configured` state
  - If pulling tokens, source addresses must have approved the contract for all redeemable tokens
- **State transition**: `configured` → `active`
- **Behavior**: Iterates through all `redeemableTokens` configured during initialization and pulls their balances from each address in the `from` array

**Example usage scenarios**:

```solidity
// Scenario 1: Tokens already transferred to contract manually
claim.startClaim([]);

// Scenario 2: Pull all redeemable tokens from a single treasury
address[] memory sources = new address[](1);
sources[0] = treasuryAddress;
claim.startClaim(sources);

// Scenario 3: Pull all redeemable tokens from multiple sources
address[] memory sources = new address[](3);
sources[0] = treasury1;
sources[1] = treasury2;
sources[2] = multisig;
claim.startClaim(sources);
// This will pull DAI and RETH (all redeemableTokens) from all 3 addresses
```

### User Functions

**`claim()`**
- **Purpose**: Users burn their TEC tokens to receive proportional redeemable tokens
- **Requirements**:
  - Contract must be in `active` state
  - User must have TEC tokens
  - User must not be blocklisted
- **Effects**: Burns user's TEC tokens, transfers proportional DAI and RETH

### Owner Functions

**`claimRemaining()`** - Owner only
- **Purpose**: After deadline, owner claims remaining unclaimed tokens
- **Requirements**:
  - Contract must be in `active` state
  - Current time must be past `claimDeadline`
- **State transition**: `active` → `finialized`

**`blockAddresses(address[] users)`** - Owner only
- **Purpose**: Prevent specific addresses from claiming
- **Requirements**: Contract must be in `active` state

**`unblockAddresses(address[] users)`** - Owner only
- **Purpose**: Remove addresses from blocklist
- **Requirements**: Contract must be in `active` state

### View Functions

**`state()(uint8)`**
- Returns current contract state: 0=dormant, 1=configured, 2=active, 3=finialized

**`claimDeadline()(uint64)`**
- Returns Unix timestamp when claim period ends

**`blocklist(address)(bool)`**
- Returns whether an address is blocklisted

**`owner()(address)`**
- Returns contract owner address

## Getting Deployment Information

To view deployment details:

```bash
# List all deployments
npx hardhat ignition deployments

# View specific deployment info
npx hardhat ignition status chain-10
```

The deployment artifacts are stored in `ignition/deployments/` directory.

## Upgrade Contract (UUPS Pattern)

The TECClaim contract uses the UUPS (Universal Upgradeable Proxy Standard) pattern. To upgrade:

### Option 1: Manual Upgrade

1. Deploy new implementation contract:
   ```bash
   # Update ignition module to deploy new implementation only
   npx hardhat ignition deploy ignition/modules/TECClaimV2.ts --network optimism
   ```

2. Call `upgradeToAndCall()` from owner address:
   ```solidity
   // From owner address
   tecClaim.upgradeToAndCall(newImplementationAddress, "");
   ```

3. Verify new implementation on Optimistic Etherscan

### Option 2: Create Upgrade Module

Create a new Ignition module for upgrades:

```typescript
// ignition/modules/UpgradeTECClaim.ts
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("UpgradeTECClaimModule", (m) => {
  const proxyAddress = m.getParameter("proxyAddress");
  const newImplementation = m.contract("TECClaimV2", []);
  
  // Upgrade logic here
  
  return { newImplementation };
});
```

**Important**: Test upgrades thoroughly on local/testnet before mainnet!

## Troubleshooting

### "Artifact for contract 'ERC1967Proxy' not found"

**Problem**: Hardhat Ignition cannot find the ERC1967Proxy artifact.

**Solution**: This issue is resolved by using TECClaimFactory instead of directly deploying ERC1967Proxy. The factory handles proxy creation internally. Ensure `contracts/TECClaimFactory.sol` exists and is compiled:

```bash
npx hardhat compile
```

The factory will automatically create ERC1967Proxy instances when you call the `create` function.

### Deployment Fails with Gas Issues

- Check you have enough ETH for gas (at least 0.01 ETH on Optimism)
- Verify RPC URL is accessible and responding
- Try increasing gas limit in hardhat.config.ts
- Check network congestion and try again later

### Invalid Address Error

- Verify all addresses are valid checksummed addresses
- Use a checksumming tool if needed: https://ethsum.netlify.app/
- Double-check addresses match the correct network (Optimism vs Ethereum)

### Contract Not Verified

- Wait a few minutes and try verification again
- Check Optimistic Etherscan API is accessible
- Try manual verification on Optimistic Etherscan if auto-verification fails
- Ensure you're verifying with the correct compiler version (0.8.28)

### Can't Call Contract Functions

- Ensure you're calling the **proxy address**, not the implementation address
- Check you have the correct owner address for owner-only functions
- Verify transaction is being sent from the owner address
- Check deadline hasn't passed for time-sensitive functions
- Ensure contract has been properly initialized

### Local Node Issues

- If port 8545 is in use: `kill -9 $(lsof -ti:8545)`
- If forking fails, check your RPC URL and API limits
- Try clearing the fork cache: `rm -rf cache/edr-fork-cache/`

## Security Recommendations

1. **Use Multisig for Owner**: 
   - Deploy with owner as a Gnosis Safe multisig on Optimism
   - Requires multiple signatures for sensitive operations
   - Protects against single point of failure

2. **Test Thoroughly**:
   - Test on local forked network first
   - Run full test suite: `npx hardhat test`
   - Test all edge cases and failure scenarios
   - Verify upgrade mechanism if planning upgrades

3. **Smart Contract Audit**:
   - Get professional audit before mainnet deployment
   - Review audit findings and implement fixes
   - Consider bug bounty program

4. **Monitoring & Alerts**:
   - Set up monitoring for `Claim` events
   - Monitor `AddressBlocked`/`AddressUnblocked` events
   - Track contract token balances
   - Set up alerts for unusual activity

5. **Secure Key Management**:
   - Use hardware wallet for owner address
   - Never share private keys
   - Store deployment information securely
   - Keep backups of all addresses and parameters

6. **Documentation**:
   - Document all deployment addresses
   - Save deployment IDs from Ignition
   - Keep record of all configuration parameters
   - Document upgrade procedures if applicable

## Additional Resources

- **Contract Source**: `contracts/TECClaim.sol`
- **Test Suite**: `contracts/TECClaim.t.sol`
- **Ignition Module**: `ignition/modules/TECClaim.ts`
- **Hardhat Config**: `hardhat.config.ts`
- **OpenZeppelin UUPS**: https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable
- **Hardhat Ignition Docs**: https://hardhat.org/ignition/docs
- **Optimistic Etherscan**: https://optimistic.etherscan.io

## Support

For issues or questions:
- Check test suite for examples: `contracts/TECClaim.t.sol`
- Review contract code in detail: `contracts/TECClaim.sol`
- Check Hardhat Ignition documentation
- Review this deployment guide thoroughly

