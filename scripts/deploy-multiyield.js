require('dotenv').config()

const hre = require("hardhat");
const manualCompundorAddress = '0x07cBe0C43c0924782623c1e78769F3112B77041F'; // Replace this with our deployed compoundor

async function main(compoundorAddress) {
  const { gasPrice } = await hre.ethers.provider.getFeeData();
  const signer = new hre.ethers.Wallet(process.env.DEPLOYMENT_PRIVATE_KEY, hre.ethers.provider)

  console.log("Deploying on", hre.network.name)

  const constructorArguments = [compoundorAddress]
  const contractFactory = await hre.ethers.getContractFactory("MultiYield", signer);
  const deployTx = await contractFactory.getDeployTransaction(...constructorArguments, { gasPrice })
  const gasLimit = await hre.ethers.provider.estimateGas(deployTx)
  const contract = await contractFactory.deploy(...constructorArguments, {
    gasPrice,
    gasLimit: gasLimit.mul(12).div(10)
  });
  await contract.deployed()

  //await contract.transferOwnership(process.env.MULTISIG_ACCOUNT);

  console.log("Deployed at", contract.address)

  console.log("Verifying contract", contract.address)
  await hre.ethers.provider.waitForTransaction(contract.deployTransaction.hash, 6)
  await hre.run("verify:verify", {
    address: contract.address,
    constructorArguments
  });

  console.log("Verified at", contract.address)
}

module.exports = main;
