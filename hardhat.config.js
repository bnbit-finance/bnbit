require("@nomiclabs/hardhat-waffle");
require('@mangrovedao/hardhat-test-solidity');
require("hardhat-laika");
require('hardhat-deploy');
let secret= require("./secrets.json");

//fdcbab5eb3ec7e8dad8f5017fc382a24295f438966e61b7f10bf5a566a0e4d4b 
// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

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
  solidity:"0.8.10",
  paths:{
    artifacts:'./src/artifacts'
  },
  networks:{
    hardhat:{
      chainId:1337
    },
    testnet:{
      url:"https://speedy-nodes-nyc.moralis.io/a9679fa83d33a799678a5795/bsc/testnet",
      accounts:[secret.key]
    },
  }

}
