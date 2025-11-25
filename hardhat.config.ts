import hardhatToolboxViemPlugin from "@nomicfoundation/hardhat-toolbox-viem";
import { configVariable, defineConfig } from "hardhat/config";

export default defineConfig({
  plugins: [hardhatToolboxViemPlugin],
  solidity: {
    profiles: {
      default: {
        version: "0.8.28",
      },
      production: {
        version: "0.8.28",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    },
  },
  networks: {
    local: {
      type: "edr-simulated",
      chainType: "op",
      forking: {
        url: `https://lb.drpc.live/optimism/${configVariable("OPTIMISM_DRPC_API_KEY")}`,
        blockNumber: 144245110,
      },
    },
    optimism: {
      type: "http",
      url: `https://lb.drpc.live/optimism/${configVariable("OPTIMISM_DRPC_API_KEY")}`,
      chainId: 10,
    },
  },
});
