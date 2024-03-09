import deployYield from './deploy-autoyield'
import deployMultiYield from './deploy-multiyield'
import deploySelfYield from './deploy-selfyield'

const main = async () => {
  const compoundorAddress = await deployYield()
  await deployMultiYield(compoundorAddress);
  //await deploySelfYield(compoundorAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
