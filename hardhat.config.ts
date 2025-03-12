import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

import { HardhatUserConfig } from "hardhat/types";
import "@nomicfoundation/hardhat-foundry";
import "@nomicfoundation/hardhat-viem";
import "@openzeppelin/hardhat-upgrades";
import "@typechain/hardhat";
import "@nomicfoundation/hardhat-verify";

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  paths: {
    sources: "./src",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  etherscan: {
    apiKey: {
      base: process.env.ETHERSCAN_BASE_API_KEY ?? "",
    }
  },
  networks: {
    base: {
      url: process.env.RPC_URL_BASE ?? "https://mainnet.base.org",
    },
  },
};

export default config;
