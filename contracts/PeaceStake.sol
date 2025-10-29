//流动性质押案例
//合约需包含：
// 1.UUPSUpgradeable升级
// 2.AccessControlUpgradeable权限控制，且升级需要升级权限
// 3.PausableUpgradeable 可暂停
// 4.SafeERC20 安全性代币转账
// 5.Math 防止溢出检查
// 6.Address 
// 7.IERC20 需要引用ERC20进行代币奖励发放

pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import "hardhat/console.sol";

contract PeaceStake is 
Initializable,
UUPSUpgradeable,
AccessControlUpgradeable,
PausableUpgradeable 
{
    using SafeERC20 for IERC20;
    using Math for uint256;
    using Address for address;

    //设置NaviToken 池子 ID
    uint256 public constant ETH_PID = 0;

    //配置权限
    bytes32 public constant  ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    struct Pool {
        address stTokenAddress;  //质押代币的地址
        uint256 poolWeight;      //质押池的权重，影响奖励分配
        uint256 lastRewardBlock; //最新奖励区块高度
        uint256 accPeaceTokenPerST; //每个质押代币累积的 RCC 数量
        uint256 stTokenAmount;     //池中的总质押代币量
        uint256 minDepositAmount;  //最小质押金额
        uint256 unstakeLockedBlocks; //解除质押的锁定区块数
    }

    struct unstackeRequest{
        uint256 amount; //发起解除质押的金额
        uint256 unstakeBlocks; //解除质押的区块
    }

    struct User{
        //用户质押的代币数量
        uint256 stAmount; 
        //已分配的 PeaceToken数量
        uint256 finishedPeaceToken;
        //待领取 PeaceToken数量
        uint256 pendingPeaceToken;
        //解质押请求列表，每个请求包含解质押数量和解锁区块
        unstackeRequest[] requests;
    }
    //根据池子的ID，再根据用户地址，找到用户Info信息
    mapping(uint256 => mapping(address => User)) public user;

    // ------奖励相关属性 ----------//
    // Pause the withdraw function
    bool public withdrawPaused;
    // Pause the claim function
    bool public claimPaused;
    //奖励Token
    IERC20 public rewardToken;

    //流动性挖矿开始
    uint256 public startBlock;
    //流动性挖矿结束
    uint256 public endBlock;

    //每出一个块，获取到的奖励Token数量,处理单位
    uint256 public peaceTokenPreBlock;

    //池子总共权重数量
    uint256 public totalPoolWeight;

    //池子列表
    Pool[] public pool;


    //事件
    event PauseClaim();
    event UnpauseClaim();

    event PauseWithDraw();
    event UnpauseWithDraw();

    event SetStartBlock(uint256 startBlock);
    event SetEndBlock(uint256 startBlock);

    event SetPeaceTokenPerBlock(uint256 preToken);

    event SetPeaceToken(IERC20 indexed tokenaddress);

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event UpdatePool(uint256 indexed pid,uint256 blockNumber,uint256 accPeaceTokenPreST);
    event AddPool(address indexed stTokenAddress,uint256 poolWeight, uint256 lastRewardBlock, uint256 minDepositAmount, uint256 unstakeLockedBlocks);
    event SetPoolWeight(uint256 indexed pid,uint256 poolWeight);
    event Claim(address indexed sender,uint256 pid,uint256 reward);
    event RequestUnstake(address indexed sender,uint256 pid,uint256 amount);
    event WithDraw(address indexed sender,uint256 amount);
    //modify检查
    //检查池子ID是否合理
    modifier checkPid(uint256 _pid){
        require(_pid < pool.length,"invalid pid");
        _;
    }
    //检查是否可获取奖励，未被暂停
    modifier whenNotClaimPaused(){
        require(!claimPaused,"claim is paused");
        _;
    }
    //检查是否进行解除质押，未被暂停
    modifier whenNotWithdrawPaused(){
        require(!withdrawPaused,"claim is paused");
        _;
    }

    //检查是否可获取奖励
    function pauseClaim() public onlyRole(ADMIN_ROLE){
        require(!claimPaused,"claim has been already paused");

        claimPaused = true;
        
        emit PauseClaim();
    }

    function unpauseClaim() public onlyRole(ADMIN_ROLE){
        require(claimPaused,"claim has been already unpansed");

        claimPaused = false;

        emit UnpauseClaim();
    }
    //检查是否可进行提现，解除质押
    function pauseWithdraw() public onlyRole(ADMIN_ROLE){
        require(!withdrawPaused,"withdraw has been already paused");

        withdrawPaused = true;
        
        emit PauseClaim();
    }

    function unpauseWithdraw() public onlyRole(ADMIN_ROLE){
        require(withdrawPaused,"withdraw has been already unpansed");

        withdrawPaused = false;

        emit UnpauseClaim();
    }
    //---------------- 获取属性值 --------------------
        //奖励Token
    function  getRewardToken() public view returns (address){ 
        return address(rewardToken);
    }

    //流动性挖矿开始
    function getStartBlock() public view returns (uint256) {
        return startBlock;
    }
    //流动性挖矿结束
    function getEndBlock() public view returns (uint256){
        return endBlock;
    }

    //每出一个块，获取到的奖励Token数量,处理单位
    function getPeaceTokenPerBlock() public view returns (uint256){
        return peaceTokenPreBlock;
    }
    /**
     * @notice Set MetaNode token address. Can only be called by admin
     */
    function setPeaceToken(IERC20 _rewardToken) public onlyRole(ADMIN_ROLE) {
        rewardToken = _rewardToken;

        emit SetPeaceToken(rewardToken);
    }

    function initialize(
        IERC20 _rewardToken,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _peaceTokenPreBlock
    ) public initializer{
        require(_startBlock <= _endBlock && _peaceTokenPreBlock>0,"invalid initialize params");
        //初始化权限
        __AccessControl_init();
        //初始化UUPS升级合约
        __UUPSUpgradeable_init();
        //初始化暂停
        __Pausable_init();
        //给合约部署者分配超管、升级权限
        _grantRole(ADMIN_ROLE,msg.sender);
        _grantRole(UPGRADE_ROLE,msg.sender);

        setPeaceToken(_rewardToken);
        startBlock = _startBlock;
        endBlock = _endBlock;

        peaceTokenPreBlock = _peaceTokenPreBlock;
    }

    // 升级进行授权
    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADE_ROLE) override {

    }

     /**
     * @notice Update staking start block. Can only be called by admin.
     */
    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock <= endBlock, "start block must be smaller than end block");

        startBlock = _startBlock;

        emit SetStartBlock(_startBlock);
    }

    /**
     * @notice Update staking end block. Can only be called by admin.
     */
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(startBlock <= _endBlock, "start block must be smaller than end block");

        endBlock = _endBlock;

        emit SetEndBlock(_endBlock);
    }

    /**
     * @notice Update the MetaNode reward amount per block. Can only be called by admin.
     */
    function setPeaceTokenPerBlock(uint256 _PeaceTokenPerBlock) public onlyRole(ADMIN_ROLE) {
        require(_PeaceTokenPerBlock > 0, "invalid parameter");

        peaceTokenPreBlock = _PeaceTokenPerBlock;

        emit SetPeaceTokenPerBlock(_PeaceTokenPerBlock);
    }
    // function getRewardTokenAddress() public returns (address){
    //     return address(rewardToken);
    // }

    /**
    *添加和更新质押池
    *输入参数: 质押代币地址(_stTokenAddress)，池权重(_poolWeight)，最小质押金额(_minDepositAmount)，解除质押锁定区(_unstakeLockedBlocks)。
    *前置条件: 只有管理员可操作。
    *后置条件: 创建新的质押池或更新现有池的配置。
    *异常处理: 权限验证失败或输入数据验证失败。
     */
    function addPool(address _stTokenAddress,uint256 _poolWeight,uint256 _minDepositAmount,uint256 _unstakeLockedBlocks,bool _isUpdate) public onlyRole(ADMIN_ROLE) {
        //默认池子第一个元素为ETH 原生代币池子
        if (pool.length == 0){
            require(_stTokenAddress == address(0x0),"First pool must be ETH pool");
        }else{
            require(_stTokenAddress != address(0x0),"Non-first pool cannot be ETH pool");
        }
        require(_poolWeight>0,"invalid poolWeight");
        require(_minDepositAmount>0,"_minDepositAmount must be grather than 0");
        require(block.number < endBlock,"Already ended");

        // 手动发更新所有池子
        if(_isUpdate){
            //更新所有池子
            allPoolUpdate();
        }
        // 累计所有当前所有池子权重总数
        //优化gas ：： 先缓存storage变量的值，在进行操作，不要直接操作storage变量
        totalPoolWeight+= _poolWeight;
        // uint256 temptotalPoolWeight = totalPoolWeight;
        // temptotalPoolWeight += _poolWeight;
        // totalPoolWeight = temptotalPoolWeight;
        
        //防止状态污染，放到池子层，当添加池子时，为每个池子更新为最新的奖励区块高度
        uint256 lastRewardBlock = block.number>startBlock ? block.number : startBlock;


        Pool memory _pool = Pool({
            stTokenAddress:_stTokenAddress,  //质押代币的地址
            poolWeight:_poolWeight,      //质押池的权重，影响奖励分配
            lastRewardBlock:lastRewardBlock, //最新奖励区块高度
            accPeaceTokenPerST:0, //每个质押代币累积的 RCC 数量
            stTokenAmount:0,     //池中的总质押代币量
            minDepositAmount:_minDepositAmount, //最小质押金额
            unstakeLockedBlocks:_unstakeLockedBlocks //解除质押的锁定区块数
            });

        //添加进入池子
        pool.push(_pool);

        //添加添加池子事件
        emit AddPool(_stTokenAddress, _poolWeight, lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }
    //更改池子权重
    function setPoolWeight(uint256 _pid,uint256 _poolWeight,bool isUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid){
        Pool storage pool_ = pool[_pid];
        require(_poolWeight > 0,"invalid pool weight");
        if (isUpdate){
            allPoolUpdate();
        }
        pool_.poolWeight = _poolWeight;
        emit SetPoolWeight(_pid,_poolWeight);
    }
    //更新池子队列中所有池子的状态，包括用户状态，池子状态等
    function allPoolUpdate() public {
        //gas优化，使用uint256 / 缓存长度 / ++i
        // for(uint pid=0;pid<pool.length;pid++){
        //     updatePool(pid);
        // }
        uint256 poolLen = pool.length;
        for (uint256 pid=0;pid<poolLen;++pid){
            updatePool(pid);
        }
    }
    //更新池子
    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];
        if (pool_.lastRewardBlock >= block.number) {
            return;
        }
        
        //计算乘数
        uint256 multiplier = _calculateMultiplier(pool_.lastRewardBlock);
        
        //计算池子奖励
        uint256 rewardTotalTokenPrePool = _calculatePoolReward(multiplier, pool_.poolWeight);
        
        uint256 stSupply = pool_.stTokenAmount;
        if (stSupply > 0) {
            pool_.accPeaceTokenPerST = _calculateAccReward(rewardTotalTokenPrePool, stSupply, pool_.accPeaceTokenPerST);
        }
        
        pool_.lastRewardBlock = block.number;
        emit UpdatePool(_pid, pool_.lastRewardBlock, pool_.accPeaceTokenPerST);
    }
    
    function _calculateMultiplier(uint256 lastRewardBlock) internal view returns (uint256) {
        // console.log(startBlock);
        if (startBlock > block.number) {
            // console.log(1111);
            (bool success, uint256 multiplier) = lastRewardBlock.trySub(startBlock);
            require(success, "overflow");
            return multiplier;
        } else if (lastRewardBlock > endBlock) {
                        // console.log(2222);
            (bool success, uint256 multiplier) = endBlock.trySub(block.number);
            require(success, "overflow");
            return multiplier;
        } else {
            // console.log(3333);
            // console.log("lastRewardBlock",lastRewardBlock);
            (bool success, uint256 multiplier) = block.number.trySub(startBlock);
            require(success, "overflow");
            return multiplier;
        }
    }
    
    function _calculatePoolReward(uint256 multiplier, uint256 poolWeight) internal view returns (uint256) {
        (bool success1, uint256 rewardTotalTokenAllPool) = multiplier.tryMul(peaceTokenPreBlock);
        require(success1, "overflow");
        
        (bool success2, uint256 rewardTotalTokenWeight) = rewardTotalTokenAllPool.tryMul(poolWeight);
        require(success2, "overflow");
        
        (bool success3, uint256 rewardTotalTokenPrePool) = rewardTotalTokenWeight.tryDiv(totalPoolWeight);
        require(success3, "overflow");
        
        return rewardTotalTokenPrePool;
    }
    
    function _calculateAccReward(uint256 rewardTotalTokenPrePool, uint256 stSupply, uint256 currentAccReward) internal pure returns (uint256) {
        (bool success11, uint256 totalRewardTokenAmount) = rewardTotalTokenPrePool.tryMul(18);
        require(success11, "overflow");
        
        (bool success21, uint256 totalRewardTokenPreStTokenAmount) = totalRewardTokenAmount.tryDiv(stSupply);
        require(success21, "overflow");
        
        (bool success31, uint256 newAccReward) = currentAccReward.tryAdd(totalRewardTokenPreStTokenAmount);
        require(success31, "overflow");
        
        return newAccReward;
    }


    /**
    *质押功能
    *输入参数: 池 ID(_pid)，质押数量(_amount)。
    *前置条件: 用户已授权足够的代币给合约。
    *后置条件: 用户的质押代币数量增加，池中的总质押代币数量更新。
    *异常处理: 质押数量低于最小质押要求时拒绝交易。
     */
    
    function depositETH() public whenNotPaused() payable {
        Pool storage pool_ = pool[ETH_PID];
        require(pool_.stTokenAddress == address(0x0), "invalid staking token address");

        uint256 _amount = msg.value;
        
        require(_amount >= pool_.minDepositAmount, "deposit amount is too small");

        // 使用payable表示已经接收ETH，更新池子的最新奖励收益，更新用户质押状态，更新用户奖励状态，更新池子累加奖励
        // emit Deposit(msg.sender,ETH_PID,msg.value);
        _deposit(ETH_PID, _amount);

    }

    function deposit(uint256 _pid,uint256 _amount) public whenNotPaused() checkPid(_pid){
        require(_pid!=0,"current deposit function not support ETH staking,please use depositETH!");
        Pool storage pool_ = pool[_pid];
        require(_amount>pool_.minDepositAmount,"deposit amount is too small");

        if (_amount>0) {
           (bool success) = IERC20(pool_.stTokenAddress).transferFrom(msg.sender,address(this),_amount);
           require(success,"transfer error");
        }
        //更新池子的最新奖励收益，更新用户质押状态，更新用户奖励状态，更新池子累加奖励 ,同上deposit ETH，
        _deposit(_pid, _amount);
        // emit Deposit(msg.sender,_pid,_amount);
    }

    function _deposit(uint256 _pid,uint256 _amount) internal {
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];
        //质押前做一次手动更新池子
        updatePool(_pid);
        //如果用户当前质押的代币大于0就计算奖励状态
        if(user_.stAmount >0){
            //计算总的每个质押代币获取的奖励Peace Token的总数
            (bool success,uint256 accST) = user_.stAmount.tryMul(pool_.accPeaceTokenPerST);
            require(success, "user stAmount mul accMetaNodePerST overflow");
            //将奖励代币金额换成成代币数量，方便计数
            (success,accST) = accST.tryDiv(18);
            require(success,"accST div rewardTokenDecimals overflow");
            //获取总的待未领取的代币总数
            (bool success2,uint256 pendingPeaceToken_) = accST.trySub(user_.finishedPeaceToken);
            require(success2,"accST sub finishedMetaNode overflow");
            if (pendingPeaceToken_>0){
                //累计待领取的奖励代币
                (bool success3,uint256 _pendingPeaceToken) = user_.pendingPeaceToken.tryAdd(pendingPeaceToken_);
                require(success3,"user pendingPeaceToken overflow");
                user_.pendingPeaceToken = _pendingPeaceToken;
            }
        }
        
        if(_amount>0) {
            //更新用户状态，累计质押代币数量
            (bool success, uint256 newStAmount) = user_.stAmount.tryAdd(_amount);
            require(success, "user stAmount overflow");
            user_.stAmount = newStAmount;
        }
        //更新池子状态 - 质押代币数量
        (bool success5,uint256 _stTokenAmount) = pool_.stTokenAmount.tryAdd(_amount);
        require(success5, "pool stTokenAmount overflow");
        pool_.stTokenAmount = _stTokenAmount;

        //更新用户状态 - 领取代币奖励的数量
        (bool success6,uint256 finishedPeaceToken) = user_.stAmount.tryMul(pool_.accPeaceTokenPerST);
        require(success6,"user stAmount mul accMetaNodePerST overflow");
        //换算成数量
        (success6,finishedPeaceToken) = finishedPeaceToken.tryDiv(18);
        require(success6, "finishedMetaNode div 1 ether overflow");

        user_.finishedPeaceToken = finishedPeaceToken;
        emit Deposit(msg.sender, _pid, _amount);

    }

    /**
    *领取奖励
    *输入参数: 池 ID(_pid)。
    *前置条件: 有可领取的奖励。
    *后置条件: 用户领取其奖励，清除已领取的奖励记录。
    *异常处理: 如果没有可领取的奖励，不执行任何操作。
    */
    //

    //全额提取奖励，提取前需要添加暂停功能
    function claim(uint256 _pid) public whenNotPaused checkPid(_pid) whenNotClaimPaused(){
        //检查是否有可领取的奖励
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        //同样提取奖励前，手动更新池子，更新池子、用户获取奖励状态
        updatePool(_pid);

        //获取用户待领取奖励数量
        (bool success,uint256 penddingRewardPeaceToken_) = user_.stAmount.tryMul(pool_.accPeaceTokenPerST);
        require(success,"overflow");
        //单位换算成数量，数量更好计算
        (success,penddingRewardPeaceToken_) = penddingRewardPeaceToken_.tryDiv(18);
        //用户待领取的奖励 = 用户质押池中的总奖励 - 已分配的奖励 + 用户待领取的奖励
        (success,penddingRewardPeaceToken_) = penddingRewardPeaceToken_.trySub(user_.finishedPeaceToken);
        (success,penddingRewardPeaceToken_) = penddingRewardPeaceToken_.tryAdd(user_.pendingPeaceToken);

        if (penddingRewardPeaceToken_>0){
            //提取奖励，先进行状态修改再进行转账
            user_.pendingPeaceToken = 0;
            //更新用户已分配的奖励
            user_.finishedPeaceToken = user_.stAmount * pool_.accPeaceTokenPerST / (18);
            safePeaceTokenTransferFROM(msg.sender, penddingRewardPeaceToken_);
        }else{
            //更新用户已分配的奖励
            user_.finishedPeaceToken = user_.stAmount * pool_.accPeaceTokenPerST / (18);
        }

        emit Claim(msg.sender,_pid,penddingRewardPeaceToken_);
        
    } 

    function safePeaceTokenTransferFROM(address _to,uint256 _amount) internal {
        //判断当前合约是否存在奖励代币
        uint256 peaceTokenBal = rewardToken.balanceOf(address(this));
        //如果提取奖励的总额，大于当前合约全部的奖励代币总额，则将当前合约的奖励全部提取
        if(_amount>peaceTokenBal){
            rewardToken.safeTransfer(_to, peaceTokenBal);
        }else{
            rewardToken.safeTransfer(_to, _amount);
        }

    }

     function safeETHTransfer(address _to,uint256 _amount) internal {
        /**
         * 使用 call 的情况：      
         *   ✅ 与智能合约进行复杂交互
         *   ✅ 需要调用特定函数并传递数据
         *   ✅ 接收方合约需要较多 Gas 执行逻辑
         *   ✅ 需要处理返回值数据
         * 
         */
        (bool success,bytes memory data) = address(_to).call{value:_amount}("");
        require(success,"ETH transfer call fail");
        //判断对方是否接收成功
        if (data.length>0){
            require(
                //解码data，判断是否为true
                abi.decode(data,(bool)),"ETH transfer not success"
            );
        }

    }
    /**
     * 解除质押
     * 
     *发起质押请求，会部分缓存起来
     */
    // 
    function unstake(uint256 _pid,uint256 _amount) public whenNotPaused() whenNotWithdrawPaused() checkPid(_pid){
        Pool storage pool_ = pool[_pid];
        User storage user_ = user[_pid][msg.sender];

        require(user_.stAmount >= _amount,"Not enough staking token balance");

        updatePool(_pid);
        //解除质押，需要进行用户状态的更新，更新用户的奖励数
        uint256 pendingPeaceToken_ = user_.stAmount * pool_.accPeaceTokenPerST / (18) - user_.finishedPeaceToken;
        //更新用户奖励
        if(pendingPeaceToken_>0){
            user_.pendingPeaceToken = user_.pendingPeaceToken + pendingPeaceToken_;

        }
        //更新用户
        if (_amount>0){
            //先进行用户状态更新
            user_.stAmount = user_.stAmount - _amount;
            //在发送解除质押请求
            user_.requests.push(unstackeRequest({
                amount:_amount,
                unstakeBlocks: block.number + pool_.unstakeLockedBlocks
            }));
        }
        //更新池子状态，池子质押代币的数量减少
        pool_.stTokenAmount = pool_.stTokenAmount - _amount;
        user_.finishedPeaceToken = user_.stAmount * pool_.accPeaceTokenPerST / (18);
        emit RequestUnstake(msg.sender, _pid, _amount);
    }

    //提现操作
    function withdraw(uint256 _pid) public whenNotPaused() checkPid(_pid) whenNotWithdrawPaused(){
        Pool storage pool_ = pool[_pid];     
        User storage user_ = user[_pid][msg.sender];
        for(uint256 i =user_.requests.length;i>0;--i){
            uint256 amount_ = user_.requests[i-1].amount;
            uint256 unblockNumber_ =user_.requests[i-1].unstakeBlocks;
            if (block.number < unblockNumber_){
                //更新用户状态
                user_.stAmount = user_.stAmount - amount_;
                //更新池子质押
                pool_.stTokenAmount = pool_.stTokenAmount - amount_;
                
                //判断_pid提取是原生代币，还是ERC20标准代币
                require(pool_.stTokenAmount>amount_,"withdraw amount is not enougth");
                if(pool_.stTokenAddress==address(0x0)){
                    safeETHTransfer(msg.sender, amount_);
                }else{
                continue;
            }
        }
    }

}
}