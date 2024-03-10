import {task} from "hardhat/config";

require('dotenv').config()
require("hardhat-contract-sizer");

import "@nomicfoundation/hardhat-toolbox"

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
export default {
  mocha: {
    timeout: 100000000
  },
  solidity: {
    version: "0.8.23",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
    },
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY_MAINNET,
      polygon: process.env.ETHERSCAN_API_KEY_POLYGON,
      optimisticEthereum: process.env.ETHERSCAN_API_KEY_OPTIMISM,
      arbitrumOne: process.env.ETHERSCAN_API_KEY_ARBITRUM,
      bsc: process.env.ETHERSCAN_API_KEY_BNB,

      // testnets
      goerli: process.env.ETHERSCAN_API_KEY_MAINNET,
    },
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://eth-mainnet.alchemyapi.io/v2/" + process.env.ALCHEMY_KEY,
        blockNumber: 14667418 // 2022-04-27
      }
    },
    polygon: {
      url: "https://rpc.ankr.com/polygon",
      chainId: 137
    },
    mainnet: {
      url: "https://rpc.ankr.com/eth",
      chainId: 1
    },
    optimism: {
      url: "https://rpc.ankr.com/optimism",
      chainId: 10
    },
    arbitrum: {
      url: "https://rpc.ankr.com/arbitrum",
      chainId: 42161
    },
    bnb: {
      url: "https://bsc-dataseed.binance.org",
      chainId: 56
    },
    goerli: {
      url: "https://rpc.ankr.com/eth_goerli",
      chainId: 5
    },
    evmos: {
      url: "https://evmos-evm.publicnode.com",
      chainId: 9001
    }
  }
};
