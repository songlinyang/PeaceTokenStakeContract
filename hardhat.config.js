require("@nomicfoundation/hardhat-toolbox");
require("hardhat-deploy");
require('@openzeppelin/hardhat-upgrades');
require("solidity-coverage");
require("hardhat-gas-reporter");
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  namedAccounts:{
    deployer:0,
    user1:1,
    user2:2
  },
  // networks:{
  //   sepolia:{
  //     url:`https://sepolia.infura.io/v3/xxx`,
  //     accounts:["your wallet key"]
  //   }
  // },
  gasReporter: {
  	 //doc:https://github.com/cgewecke/eth-gas-reporter
    enabled: true,
    currency: "USD", //默认EUR, 可选USD, CNY, HKD
    outputFile: 'v2-gas-report.txt', // 将报告输出到文件
    // 默认token是ETH， 更换成其他的会实时在coinmarketcap找价格
    // token: "MATIC",
    // coinmarketcap: "59a52916-XXXX-XXXX-XXXX-2d6f56917aee", //https://coinmarketcap.com/

    // 默认从 eth gas station api 中获取eth价格，其他代币可自行输入gasPrice（推荐）， 或填入gasPriceAPI（注意调用限制）
    // gasPrice: 30,
    // gasPriceApi:"https://api.etherscan.io/api?module=proxy&amp;action=eth_gasPrice",
  },
  plugins:['solidity-coverage'], //插入此行启用覆盖率插件
  //配置solidity- coverage的示例选项
  settings:{
    coverage:{
      excludeFiles:[], //排除
    }
  }
};

task("accounts","Prints the list of accounts",async (taskArgs, hre)=>{
  const accounts = await hre.ethers.getSigners();
  
  for(const account of accounts) {
    console.log(account.address);
  }
})
