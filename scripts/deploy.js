const deployCompoundor = require('./deploy-compoundor')
const deployMultiCompoundor = require('./deploy-multi-compoundor')

const main = async () => {
  const compoundorAddress = await deployCompoundor()
  await deployMultiCompoundor(compoundorAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
