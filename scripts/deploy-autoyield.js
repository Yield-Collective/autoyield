require('dotenv').config()

const hre = require("hardhat");

const nonfungiblePositionManagerAddress = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
const swapRouterAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"

async function main() {
  const { gasPrice } = await hre.ethers.provider.getFeeData();
  const signer = new hre.ethers.Wallet(process.env.DEPLOYMENT_PRIVATE_KEY, hre.ethers.provider)

  console.log("Deploying on", hre.network.name)

  const constructorArguments = [nonfungiblePositionManagerAddress, swapRouterAddress]
  const contractFactory = await hre.ethers.getContractFactory("AutoYield", signer);
  const deployTx = await contractFactory.getDeployTransaction(...constructorArguments, { gasPrice })
  const gasLimit = await hre.ethers.provider.estimateGas(deployTx)
  const contract = await contractFactory.deploy(...constructorArguments, {
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
    constructorArguments
  });

  console.log("Verified at", contract.address)

  return contract.address
}

module.exports = main;
