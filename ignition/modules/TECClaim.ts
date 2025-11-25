import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Deployment module for TECClaim contract (UUPS Upgradeable)
 * 
 * Configuration variables needed:
 * - TOKEN_MANAGER_ADDRESS: Address of the TokenManager contract
 * - DAI_ADDRESS: Address of DAI token
 * - RETH_ADDRESS: Address of RETH token (or other redeemable tokens)
 * - CLAIM_DEADLINE: Unix timestamp for claim deadline (seconds)
 * - OWNER_ADDRESS: Address of the contract owner
 */
export default buildModule("TECClaimModule", (m) => {
  // Get configuration parameters
  const tokenManagerAddress = m.getParameter("tokenManagerAddress");
  const daiAddress = m.getParameter("daiAddress");
  const rethAddress = m.getParameter("rethAddress");
  const claimDeadline = m.getParameter("claimDeadline");
  const ownerAddress = m.getParameter("ownerAddress");

  // Deploy the implementation contract
  const implementation = m.contract("TECClaim", [], {
    id: "TECClaim_Implementation",
  });

  // Prepare redeemable tokens array
  const redeemableTokens = [daiAddress, rethAddress];

  // Encode the initialization data
  const initData = m.encodeFunctionCall(implementation, "initialize", [
    ownerAddress,
    tokenManagerAddress,
    redeemableTokens,
    claimDeadline,
  ]);

  // Deploy the proxy contract (using our Proxy wrapper which extends ERC1967Proxy)
  const proxy = m.contract("Proxy", [implementation, initData], {
    id: "TECClaim_Proxy",
  });

  // Create a contract instance at the proxy address with the implementation ABI
  const tecClaim = m.contractAt("TECClaim", proxy, {
    id: "TECClaim",
  });

  return { 
    implementation, 
    proxy, 
    tecClaim 
  };
});

