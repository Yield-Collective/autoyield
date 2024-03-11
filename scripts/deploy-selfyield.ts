require('dotenv').config()

import hre from "hardhat"

const nonfungiblePositionManagerAddress = "0xC36442b4a4522E871399CD717aBDD847Ab11FE88"
const swapRouterAddressV2 = "0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"

export default async function main() {
  const { gasPrice } = await hre.ethers.provider.getFeeData()
  const signer = new hre.ethers.Wallet(process.env.DEPLOYMENT_PRIVATE_KEY as string, hre.ethers.provider)

  console.log("Deploying on", hre.network.name)

  const contractFactory = await hre.ethers.getContractFactory("SelfYield", signer)
  const deployTx = await contractFactory.getDeployTransaction(nonfungiblePositionManagerAddress, swapRouterAddressV2, { gasPrice })
  const gasLimit = await hre.ethers.provider.estimateGas(deployTx)
  const contract = await contractFactory.deploy(nonfungiblePositionManagerAddress, swapRouterAddressV2, {
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
    constructorArguments: [nonfungiblePositionManagerAddress, swapRouterAddressV2],
  })

  console.log("Verified at", deployedAddress)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
