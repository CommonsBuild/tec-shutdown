import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Deployment module for TECClaim contract (UUPS Upgradeable)
 * 
 * Configuration variables needed:
 * - TEC_TOKEN_ADDRESS: Address of the source TEC MiniMe token (to create snapshot from)
 * - DAI_ADDRESS: Address of DAI token
 * - RETH_ADDRESS: Address of RETH token (or other redeemable tokens)
 * - CLAIM_DEADLINE: Unix timestamp for claim deadline (seconds)
 * - OWNER_ADDRESS: Address of the contract owner
 * 
 * Note: The deployment process consists of:
 *       1. Deploy the implementation contract
 *       2. Deploy the factory contract
 *       3. Create a proxy via the factory
 *       4. Create a non-transferable snapshot token at the current block
 *       The TECClaim contract will be the controller of the snapshot token.
 */
export default buildModule("TECClaimModule", (m) => {
  // Get configuration parameters
  const tecTokenAddress = m.getParameter("tecTokenAddress");
  const daiAddress = m.getParameter("daiAddress");
  const rethAddress = m.getParameter("rethAddress");
  const claimDeadline = m.getParameter("claimDeadline");
  const ownerAddress = m.getParameter("ownerAddress");

  // Deploy the implementation contract
  const implementation = m.contract("TECClaim", [], {
    id: "TECClaim_Implementation",
  });

  // Deploy the factory contract with the implementation address
  const factory = m.contract("TECClaimFactory", [implementation], {
    id: "TECClaimFactory",
  });

  // Prepare redeemable tokens array
  const redeemableTokens = [daiAddress, rethAddress];

  // Create proxy using factory
  const proxyCreation = m.call(factory, "create", [
    ownerAddress,
    tecTokenAddress,
    redeemableTokens,
    claimDeadline,
  ], {
    id: "TECClaim_Proxy_Creation",
  });

  // Extract the proxy address from the return value
  const proxyAddress = m.readEventArgument(
    proxyCreation,
    "ProxyCreated",
    "proxy",
    {
      id: "TECClaim_Proxy_Address",
    }
  );

  // Create a contract instance at the proxy address with the implementation ABI
  const tecClaim = m.contractAt("TECClaim", proxyAddress, {
    id: "TECClaim",
  });

  return { 
    implementation, 
    factory,
    tecClaim 
  };
});

