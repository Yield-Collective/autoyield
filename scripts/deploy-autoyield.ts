require('dotenv').config()

import {AddressLike} from "ethers"
import hre from "hardhat"

const nonfungiblePositionManagerAddress = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
const swapRouterAddress = "0xE592427A0AEce92De3Edee1F18E0157C05861564"

export default async function main() {
  const { gasPrice } = await hre.ethers.provider.getFeeData()
  const signer = new hre.ethers.Wallet(process.env.DEPLOYMENT_PRIVATE_KEY as string, hre.ethers.provider)

  console.log("Deploying on", hre.network.name)

  const contractFactory = await hre.ethers.getContractFactory("AutoYield", signer)

  const constructorArguments: [AddressLike, AddressLike] = [nonfungiblePositionManagerAddress, swapRouterAddress]
  const deployTx = await contractFactory.getDeployTransaction(...constructorArguments, { gasPrice })
  const gasLimit = await hre.ethers.provider.estimateGas(deployTx)
  const contract = await contractFactory.deploy(...constructorArguments, {
    gasPrice,
    gasLimit: gasLimit * 12n / 10n
  })
  await contract.waitForDeployment()

  //await contract.transferOwnership(process.env.MULTISIG_ACCOUNT)

  const deployedAddress = await contract.getAddress()
  console.log("Deployed at", deployedAddress)
  console.log("Verifying contract", deployedAddress)
  await contract.deploymentTransaction()?.wait(6)
  await hre.run("verify:verify", {
    address: deployedAddress,
    constructorArguments
  })

  console.log("Verified at", deployedAddress)

  return deployedAddress
}
