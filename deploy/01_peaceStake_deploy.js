const { deployments,upgrades, getNamedAccounts, ethers } = require("hardhat");
const { promisify } = require('util');
const fs = require("fs");
const path = require("path");
function sleep(ms) {
  console.log("进来了");
      return new Promise(resolve => setTimeout(resolve, ms));
    }
module.exports = async({getNamedAccounts,deployments}) =>{
    const { deployer } = await getNamedAccounts();

    const { save } = deployments;

    console.log("部署用户地址：",deployer);

    const PeaceStakeFactory = await ethers.getContractFactory("PeaceStake");
    // 通过代理合约部署,通过ethers.js合约工厂来创建
    const currentBlock = await ethers.provider.getBlockNumber();
    const startBlock = currentBlock + 10;
    const endBlock = startBlock + 1000;
    const peaceTokenPerBlock = ethers.parseEther("1");
    const peaceStakeProxy = await upgrades.deployProxy(PeaceStakeFactory,[
        ethers.ZeroAddress, //测试用，填写0地址
        startBlock, //获取当前区块高度，作为质押开始的最开始区块
        endBlock, //出到1000个块时，质押结束区块
        peaceTokenPerBlock //每生成一个块奖励10个Peacetoken
    ],{
        initializer:"initialize"
    });
    // await peaceStakeProxy.waitForDeployment();
    await peaceStakeProxy.getDeployedCode();
    const proxyAddress = await peaceStakeProxy.getAddress();
    console.log("代理合约地址：",proxyAddress)
    const sleep = promisify(setTimeout);
    //等待延迟部署逻辑合约，因耗时过长，防止中途异常，加上延迟等待
    await sleep(20000);
    const  implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
    console.log("逻辑合约地址：", implAddress);
    
    // 保存合约和代理合约地址到json文件中
    const storePath = path.join(__dirname, "./.cache/peaceStakeProxy.json");
    fs.writeFileSync(
    storePath,
    JSON.stringify({
      proxyAddress,
      implAddress,
      abi: PeaceStakeFactory.interface.format("json"),
    })
  );

    await save("PeaceStakeProxy", {
    abi: PeaceStakeFactory.interface.format("json"),
    address: proxyAddress,
    // args: [],
    // log: true,
  })

};

module.exports.tags = ["deployPeaceStake"]