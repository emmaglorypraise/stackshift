const hre = require("hardhat");

const main = async () => {
  
  const DAO = await hre.ethers.getContractFactory("FARMSUREDAO");
  const dao = await DAO.deploy();

  await dao.deployed();

  console.log("The FARMSURE DAO contract was deployed to: ", dao.address);
}

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
};

runMain();