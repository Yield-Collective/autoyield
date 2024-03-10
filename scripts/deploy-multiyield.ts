require('dotenv').config()

import hre from "hardhat";

export default async function main(compoundorAddress: string) {
  const { gasPrice } = await hre.ethers.provider.getFeeData();
  const signer = new hre.ethers.Wallet(process.env.DEPLOYMENT_PRIVATE_KEY as string, hre.ethers.provider)

  console.log("Deploying on", hre.network.name)

  const contractFactory = await hre.ethers.getContractFactory("MultiYield", signer);
  const deployTx = await contractFactory.getDeployTransaction(compoundorAddress, { gasPrice })
  const gasLimit = await hre.ethers.provider.estimateGas(deployTx)
  const contract = await contractFactory.deploy(compoundorAddress, {
    gasPrice,
    gasLimit: gasLimit * 12n / 10n
  });
  await contract.waitForDeployment();

  //await contract.transferOwnership(process.env.MULTISIG_ACCOUNT);

  const deployedAddress = await contract.getAddress();
  console.log("Deployed at", deployedAddress)
  console.log("Verifying contract", deployedAddress)
  await new Promise(r => setTimeout(r, 30 * 1000));
  await hre.run("verify:verify", {
    address: deployedAddress,
    constructorArguments: [compoundorAddress]
  });

  console.log("Verified at", deployedAddress)
}
