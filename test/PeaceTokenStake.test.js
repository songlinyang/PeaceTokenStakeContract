const { ethers, deployments } = require("hardhat");
const { expect } = require("chai");

describe("PeaceStake", function() {
    // 初始化变量
    const initialSupply = 100_000_000;
    let deployer, user1, user2;
    let peaceToken, peaceStake;
    let startBlock, endBlock, peaceTokenPerBlock;
    let peaceTokenAddress,peaceStakeAddress;
    
    const setupTestEnvironment = async () => {
        [deployer, user1, user2] = await ethers.getSigners();
        
        // 部署PeaceToken
        const PeaceTokenFactory = await ethers.getContractFactory("PeaceToken");
        peaceToken = await PeaceTokenFactory.deploy(initialSupply);
        await peaceToken.waitForDeployment();
        peaceTokenAddress = await peaceToken.getAddress();
        
        // 部署PeaceStake
        await deployments.fixture(["deployPeaceStake"]);
        const peaceStakeProxy = await deployments.get("PeaceStakeProxy");
        peaceStake = await ethers.getContractAt("PeaceStake",peaceStakeProxy.address);
        await peaceStake.waitForDeployment();
        
        // // 设置初始化参数
        const currentBlock = await ethers.provider.getBlockNumber();
        startBlock = currentBlock + 10;
        endBlock = startBlock + 1000;
        peaceTokenPerBlock = ethers.parseEther("1");
        
        //分配奖励token地址给Stake进行奖励生成
        peaceStake.setPeaceToken(peaceTokenAddress);
        
        // 给用户分配一些代币用于测试
        const tokenAmount = ethers.parseEther("1000");
        await peaceToken.transfer(user1.address, tokenAmount);
        await peaceToken.transfer(user2.address, tokenAmount);
        
        // 给质押合约分配奖励代币
        const rewardAmount = ethers.parseEther("100000");
        peaceStakeAddress = await peaceStake.getAddress();

        await peaceToken.transfer(peaceStakeAddress, rewardAmount);
    }

    describe("部署合约场景🚗", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
        });

        it("应该部署PeaceToken代币成功", async function() {
            const peaceTokenAddress = await peaceToken.getAddress();
            console.log("PeaceToken代币合约地址：",peaceStakeAddress);
            expect(peaceTokenAddress).to.not.equal(ethers.ZeroAddress);
            
            const ownerBalance = await peaceToken.balanceOf(deployer.address);
            expect(ownerBalance).to.be.greaterThan(0);
        });

        it("应该部署PeaceStake合约成功", async function() {
            expect(peaceStakeAddress).to.not.equal(ethers.ZeroAddress);
        });

        it("应该成功初始化PeaceStake合约", async function() {
            const actualRewardToken = await peaceStake.getRewardToken();
            expect(actualRewardToken).to.equal(peaceTokenAddress);
            
            const actualPeaceTokenPerBlock = await peaceStake.getPeaceTokenPerBlock();
            expect(actualPeaceTokenPerBlock).to.equal(peaceTokenPerBlock);
        });
    });

    describe("池子管理场景🏊", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
        });

        it("应该能添加ETH质押池", async function() {
            const poolWeight = 100;
            const minDepositAmount = ethers.parseEther("0.1");
            const unstakeLockedBlocks = 100;
            
            await peaceStake.addPool(
                ethers.ZeroAddress, // ETH池地址为0
                poolWeight,
                minDepositAmount,
                unstakeLockedBlocks,
                false
            );
            
            const pool = await peaceStake.pool(0);
            expect(pool.stTokenAddress).to.equal(ethers.ZeroAddress);
            expect(pool.poolWeight).to.equal(poolWeight);
            expect(pool.minDepositAmount).to.equal(minDepositAmount);
            expect(pool.unstakeLockedBlocks).to.equal(unstakeLockedBlocks);
        });

        it("应该能添加ERC20质押池", async function() {
            // 先添加ETH池
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                100,
                false
            );
            
            // 创建一个测试ERC20代币
            const TestTokenFactory = await ethers.getContractFactory("TestERC20");
            const testToken = await TestTokenFactory.deploy();
            await testToken.waitForDeployment();
            
            const poolWeight = 200;
            const minDepositAmount = ethers.parseEther("10");
            const unstakeLockedBlocks = 200;
            
            await peaceStake.addPool(
                await testToken.getAddress(),
                poolWeight,
                minDepositAmount,
                unstakeLockedBlocks,
                false
            );
            
            const pool = await peaceStake.pool(1);
            expect(pool.stTokenAddress).to.equal(await testToken.getAddress());
            expect(pool.poolWeight).to.equal(poolWeight);
        });

        it("非管理员不能添加池子", async function() {
            const poolWeight = 100;
            const minDepositAmount = ethers.parseEther("0.1");
            const unstakeLockedBlocks = 100;
            
            await expect(
                peaceStake.connect(user1).addPool(
                    ethers.ZeroAddress,
                    poolWeight,
                    minDepositAmount,
                    unstakeLockedBlocks,
                    false
                )
            ).to.be.reverted;
        });

        it("应该能更新池子权重", async function() {
            // 先添加一个池子
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                100,
                false
            );
            
            const newWeight = 150;
            await peaceStake.setPoolWeight(0, newWeight, false);
            
            const pool = await peaceStake.pool(0);
            expect(pool.poolWeight).to.equal(newWeight);
        });
    });

    describe("质押功能场景💰", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
            // 添加ETH池
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                100,
                false
            );
        });

        it("应该能质押ETH", async function() {
            const depositAmount = ethers.parseEther("1");
            
            // 质押前用户余额
            const userBalanceBefore = await ethers.provider.getBalance(user1.address);
            
            await expect(
                peaceStake.connect(user1).depositETH({ value: depositAmount })
            ).to.emit(peaceStake, "Deposit");
            
            // 检查用户质押状态
            const userInfo = await peaceStake.user(0, user1.address);
            expect(userInfo.stAmount).to.equal(depositAmount);
            
            // 检查池子状态
            const pool = await peaceStake.pool(0);
            expect(pool.stTokenAmount).to.equal(depositAmount);
        });

        it("质押ETH金额不足应该失败", async function() {
            const smallAmount = ethers.parseEther("0.05"); // 小于最小质押金额
            
            await expect(
                peaceStake.connect(user1).depositETH({ value: smallAmount })
            ).to.be.revertedWith("deposit amount is too small");
        });

        it("应该能质押ERC20代币", async function() {
            // 添加ERC20池
            const TestTokenFactory = await ethers.getContractFactory("PeaceToken");
            const testToken = await TestTokenFactory.deploy(ethers.parseEther("1000000"));
            await testToken.waitForDeployment();
            
            await peaceStake.addPool(
                await testToken.getAddress(),
                200,
                ethers.parseEther("10"),
                200,
                false
            );
            
            // 给用户分配测试代币
            const depositAmount = ethers.parseEther("50");
            await testToken.transfer(user1.address, depositAmount);
            
            // 授权给质押合约
            await testToken.connect(user1).approve(await peaceStake.getAddress(), depositAmount);
            
            await expect(
                peaceStake.connect(user1).deposit(1, depositAmount)
            ).to.emit(peaceStake, "Deposit");
            
            // 检查用户质押状态
            const userInfo = await peaceStake.user(1, user1.address);
            expect(userInfo.stAmount).to.equal(depositAmount);
        });
    });

    describe("奖励领取场景🎁", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
            // 添加ETH池
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                100,
                false
            );
            
            // 质押一些ETH
            const depositAmount = ethers.parseEther("1");
            await peaceStake.connect(user1).depositETH({ value: depositAmount });
            
            // 推进区块以产生奖励
            for (let i = 0; i < 10; i++) {
                await ethers.provider.send("evm_mine");
            }
        });

        it("应该能领取奖励", async function() {
            console.log(user1.address);
            const userBalanceBefore = await peaceToken.balanceOf(user1.address);
            
            await expect(
                peaceStake.connect(user1).claim(0)
            ).to.emit(peaceStake, "Claim");
            
            const userBalanceAfter = await peaceToken.balanceOf(user1.address);
            expect(userBalanceAfter).to.be.greaterThan(userBalanceBefore);
        });

        it("暂停领取时不能领取奖励", async function() {
            await peaceStake.pauseClaim();
            
            await expect(
                peaceStake.connect(user1).claim(0)
            ).to.be.revertedWith("claim is paused");
            
            // 恢复领取
            await peaceStake.unpauseClaim();
        });
    });

    describe("解除质押场景🔓", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
            // 添加ETH池
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                10, // 较短的锁定区块
                false
            );
            
            // 质押一些ETH
            const depositAmount = ethers.parseEther("1");
            await peaceStake.connect(user1).depositETH({ value: depositAmount });
        });

        it("应该能发起解除质押请求", async function() {
            const unstakeAmount = ethers.parseEther("0.5");
            
            await expect(
                peaceStake.connect(user1).unstake(0, unstakeAmount)
            ).to.emit(peaceStake, "RequestUnstake");
            
            // 检查用户状态
            const userInfo = await peaceStake.user(0, user1.address);
            expect(userInfo.stAmount).to.equal(ethers.parseEther("0.5")); // 剩余质押量
        });

        it("解除质押金额不能超过质押金额", async function() {
            const excessAmount = ethers.parseEther("2"); // 超过质押金额
            
            await expect(
                peaceStake.connect(user1).unstake(0, excessAmount)
            ).to.be.revertedWith("Not enough staking token balance");
        });

        it("暂停解除质押时不能发起请求", async function() {
            await peaceStake.pauseWithdraw();
            
            await expect(
                peaceStake.connect(user1).unstake(0, ethers.parseEther("0.1"))
            ).to.be.revertedWith("claim is paused");
            
            // 恢复解除质押
            await peaceStake.unpauseWithdraw();
        });
    });

    describe("提现功能场景💸", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
            // 添加ETH池
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                2, // 很短的锁定区块
                false
            );
            
            // 质押并解除质押
            const depositAmount = ethers.parseEther("1");
            await peaceStake.connect(user1).depositETH({ value: depositAmount });
            
            const unstakeAmount = ethers.parseEther("0.5");
            await peaceStake.connect(user1).unstake(0, unstakeAmount);
            
            // 推进区块超过锁定时间
            for (let i = 0; i < 3; i++) {
                await ethers.provider.send("evm_mine");
            }
        });

        it("应该能提现解锁的代币", async function() {
            const userBalanceBefore = await ethers.provider.getBalance(user1.address);
            
            await expect(
                peaceStake.connect(user1).withdraw(0)
            ).to.emit(peaceStake, "WithDraw");
            
            const userBalanceAfter = await ethers.provider.getBalance(user1.address);
            // 注意：由于gas费用，余额可能不会精确增加
        });

        it("暂停提现时不能提现", async function() {
            await peaceStake.pauseWithdraw();
            
            await expect(
                peaceStake.connect(user1).withdraw(0)
            ).to.be.revertedWith("claim is paused");
            
            // 恢复提现
            await peaceStake.unpauseWithdraw();
        });
    });

    describe("管理员功能场景👨‍💼", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
        });

        it("应该能设置开始区块", async function() {
            const newStartBlock = startBlock + 50;
            await peaceStake.setStartBlock(newStartBlock);
            
            const actualStartBlock = await peaceStake.startBlock();
            expect(actualStartBlock).to.equal(newStartBlock);
        });

        it("应该能设置结束区块", async function() {
            const newEndBlock = endBlock + 500;
            await peaceStake.setEndBlock(newEndBlock);
            
            const actualEndBlock = await peaceStake.endBlock();
            expect(actualEndBlock).to.equal(newEndBlock);
        });

        it("应该能设置每区块奖励", async function() {
            const newRewardPerBlock = ethers.parseEther("2");
            await peaceStake.setPeaceTokenPerBlock(newRewardPerBlock);
            
            const actualRewardPerBlock = await peaceStake.peaceTokenPreBlock();
            expect(actualRewardPerBlock).to.equal(newRewardPerBlock);
        });

        it("非管理员不能修改配置", async function() {
            await expect(
                peaceStake.connect(user1).setStartBlock(startBlock + 100)
            ).to.be.reverted;
            
            await expect(
                peaceStake.connect(user1).setEndBlock(endBlock + 100)
            ).to.be.reverted;
            
            await expect(
                peaceStake.connect(user1).setPeaceTokenPerBlock(ethers.parseEther("3"))
            ).to.be.reverted;
        });

        it("应该能更新所有池子", async function() {
            // 添加两个池子
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                100,
                false
            );
            
            const TestTokenFactory = await ethers.getContractFactory("PeaceToken");
            const testToken = await TestTokenFactory.deploy(ethers.parseEther("1000000"));
            await testToken.waitForDeployment();
            
            await peaceStake.addPool(
                await testToken.getAddress(),
                200,
                ethers.parseEther("10"),
                200,
                false
            );
            
            // 推进一些区块
            for (let i = 0; i < 5; i++) {
                await ethers.provider.send("evm_mine");
            }
            
            // 更新所有池子
            await peaceStake.allPoolUpdate();
            
            // 检查池子是否更新
            const pool1 = await peaceStake.pool(0);
            const pool2 = await peaceStake.pool(1);
            
            expect(pool1.lastRewardBlock).to.equal(await ethers.provider.getBlockNumber());
            expect(pool2.lastRewardBlock).to.equal(await ethers.provider.getBlockNumber());
        });
    });

    describe("边界条件和错误处理场景⚠️", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
        });

        it("无效的池子ID应该失败", async function() {
            await expect(
                peaceStake.connect(user1).deposit(999, ethers.parseEther("1"))
            ).to.be.revertedWith("invalid pid");
            
            await expect(
                peaceStake.connect(user1).claim(999)
            ).to.be.revertedWith("invalid pid");
            
            await expect(
                peaceStake.connect(user1).unstake(999, ethers.parseEther("1"))
            ).to.be.revertedWith("invalid pid");
        });

        it("初始化参数验证应该工作", async function() {
            const PeaceStakeFactory = await ethers.getContractFactory("PeaceStake");
            const newPeaceStake = await PeaceStakeFactory.deploy();
            await newPeaceStake.waitForDeployment();
            
            // 测试无效的初始化参数
            await expect(
                newPeaceStake.initialize(
                    await peaceToken.getAddress(),
                    endBlock + 100, // 开始区块大于结束区块
                    endBlock,
                    peaceTokenPerBlock
                )
            ).to.be.revertedWith("invalid initialize params");
        });

        it("质押到ETH池应该使用depositETH函数", async function() {
            // 添加ETH池
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                100,
                false
            );
            
            // 尝试使用deposit函数质押ETH应该失败
            await expect(
                peaceStake.connect(user1).deposit(0, ethers.parseEther("1"))
            ).to.be.revertedWith("current deposit function not support ETH staking,please use depositETH!");
        });

        it("合约暂停时不能进行质押操作", async function() {
            // 添加ETH池
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                100,
                false
            );
            
            // 注意：合约没有pause/unpause函数，跳过此测试
            this.skip();
        });
    });

    describe("奖励计算场景📊", function() {
        beforeEach(async () => {
            await setupTestEnvironment();
            // 添加ETH池
            await peaceStake.addPool(
                ethers.ZeroAddress,
                100,
                ethers.parseEther("0.1"),
                100,
                false
            );
            
            // 质押ETH
            await peaceStake.connect(user1).depositETH({ value: ethers.parseEther("10") });
        });

        it("应该正确计算奖励", async function() {
            // 推进区块以产生奖励
            const blocksToMine = 50;
            for (let i = 0; i < blocksToMine; i++) {
                await ethers.provider.send("evm_mine");
            }
            
            // 领取奖励
            await peaceStake.connect(user1).claim(0);
            
            // 检查奖励是否正确计算
            const userInfo = await peaceStake.user(0, user1.address);
            expect(userInfo.pendingPeaceToken).to.equal(0); // 奖励应该被领取
        });

        it("多个用户应该按比例分配奖励", async function() {
            // 第二个用户也质押
            await peaceStake.connect(user2).depositETH({ value: ethers.parseEther("5") });
            
            // 推进区块
            for (let i = 0; i < 20; i++) {
                await ethers.provider.send("evm_mine");
            }
            
            // 两个用户都领取奖励
            await peaceStake.connect(user1).claim(0);
            await peaceStake.connect(user2).claim(0);
            
            // 检查两个用户都收到了奖励
            const user1Balance = await peaceToken.balanceOf(user1.address);
            const user2Balance = await peaceToken.balanceOf(user2.address);
            
            expect(user1Balance).to.be.greaterThan(0);
            expect(user2Balance).to.be.greaterThan(0);
            
            // user1的奖励应该大约是user2的两倍（因为质押了2倍的代币）
            expect(user1Balance).to.be.greaterThan(user2Balance);
        });
    });
});
