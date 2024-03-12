require('dotenv').config()

import {AddressLike} from "ethers"
import hre from "hardhat"

export default async function main(compoundorAddress: string) {
  const { gasPrice } = await hre.ethers.provider.getFeeData()
  const signer = new hre.ethers.Wallet(process.env.DEPLOYMENT_PRIVATE_KEY as string, hre.ethers.provider)

  console.log("Deploying on", hre.network.name)

  const constructorArguments: [AddressLike] = [compoundorAddress]
  const contractFactory = await hre.ethers.getContractFactory("MultiYield", signer);
  const deployTx = await contractFactory.getDeployTransaction(...constructorArguments, { gasPrice })
  const gasLimit = await hre.ethers.provider.estimateGas(deployTx)
  const contract = await contractFactory.deploy(...constructorArguments, {
    gasPrice,
    gasLimit: gasLimit * 12n / 10n
  });
  await contract.waitForDeployment()

  //await contract.transferOwnership(process.env.MULTISIG_ACCOUNT);

  const deployedAddress = await contract.getAddress()
  console.log("Deployed at", deployedAddress)
  console.log("Verifying contract", deployedAddress)
  await contract.deploymentTransaction()?.wait(30)
  await hre.run("verify:verify", {
    address: deployedAddress,
    constructorArguments: constructorArguments
  })

  console.log("Verified at", deployedAddress)
}
