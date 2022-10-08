require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-truffle5");
require('dotenv').config()

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async () => {
  const accounts = await ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    okchain: {
      url: process.env.RPC_URL_OK,
      accounts: [process.env.PK_ACCOUNT_1],
      timeout: 600000,
      blockGasLimit: 0x1fffffffffffff,
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      allowUnlimitedContractSize: true,
      blockGasLimit: 0x1fffffffffffff
    },
    bsc: {
      url: process.env.RPC_URL_BSC,
      accounts: [process.env.PK_ACCOUNT_1],
      timeout: 600000
    },
    goerli: {
      url: process.env.RPC_URL_goerli,
      accounts: [process.env.PK_ACCOUNT_1],
      timeout: 600000
    }
  },
  solidity: "0.6.12",
};

