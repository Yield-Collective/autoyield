import deployYield from './deploy-autoyield'
import deployMultiYield from './deploy-multiyield'

const main = async () => {
  const compoundorAddress = await deployYield()
  await deployMultiYield(compoundorAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
