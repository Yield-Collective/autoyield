require('dotenv').config()

const hre = require("hardhat");

const nativeTokenAddresses = {
  "mainnet" : "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  "polygon" : "0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270",
  "optimism" : "0x4200000000000000000000000000000000000006",
  "arbitrum" : "0x82af49447d8a07e3bd95bd0d56f35241523fbab1",
  "goerli" : "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6"
}

const nonfungiblePositionManagerAddress = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
const swapRouterAddressV2 = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"

async function main() {
  const { gasPrice } = await hre.ethers.provider.getFeeData();
  const signer = new hre.ethers.Wallet(process.env.DEPLOYMENT_PRIVATE_KEY, hre.ethers.provider)

  console.log("Deploying on", hre.network.name)

  const nativeTokenAddress = nativeTokenAddresses[hre.network.name]

  const contractFactory = await hre.ethers.getContractFactory("SelfCompoundor", signer);
  const deployTx = await contractFactory.getDeployTransaction(nonfungiblePositionManagerAddress, swapRouterAddressV2, { gasPrice })
  const gasLimit = await hre.ethers.provider.estimateGas(deployTx)
  const contract = await contractFactory.deploy(nonfungiblePositionManagerAddress, swapRouterAddressV2, {
    gasPrice,
    gasLimit: gasLimit.mul(12).div(10)
  });
  await contract.deployed();

  //await contract.transferOwnership(process.env.MULTISIG_ACCOUNT);

  console.log("Deployed at", contract.address)
  console.log("Verifying contract", contract.address)
  await hre.ethers.provider.waitForTransaction(contract.deployTransaction.hash, 6)
  await hre.run("verify:verify", {
    address: contract.address,
    constructorArguments: [
      nonfungiblePositionManagerAddress,
      swapRouterAddressV2
    ],
  });

  console.log("Verified at", contract.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
