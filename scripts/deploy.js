const deployYield = require('./deploy-autoyield')
const deployMultiYield = require('./deploy-multiyield')
const deploySelfYield = require('./deploy-selfyield')

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
