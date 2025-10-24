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
import "@oepnzeppelin/contracts/utils/math/Math.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract PeaceStake is 
Initializable,
UUPSUpgradeable,
AccessControlUpgradeable,
PausableUpgradeable 
{
    using SafeERC20 for IERC20;
    using Math for unit256;
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
    uint255 public peaceTokenPreBlock;

    //池子总共权重数量
    uint256 public totalPoolWeight;

    //池子列表
    Pool[] public pool;


    //事件
    event PauseClaim();
    event UnpauseClaim();

    event Deposit(address indexed user, uint256 indexed poolId, uint256 amount);
    event UpdatePool(uint256 indexed pid,uint256 blockNumber,uint256 accPeaceTokenPreST);
    event addPool(address indexed stTokenAddress,uint256 poolWeight, uint256 lastRewardBlock, uint256 minDepositAmount, uint256 unstakeLockedBlocks);
    event setPoolWeight(uint256 indexed pid,uint256 poolWeight);
    //modify检查
    //检查池子ID是否合理
    modifier checkPid(uint256 pid){
        require(_pid>0 && _pid<pool.length,"invalid pid");
    }
    //检查是否可获取奖励，未被暂停
    modifier whenNotClaimPaused(){
        require(!claimPaused,"claim is paused");
    }

    //检查是否可解除质押
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

    function initialize(
        IERC20 _rewardToken,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _peaceTokenPreBlock
    ) public initializer{
        require(_startBlock>=_endBlock && _peaceTokenPreBlock>0,"invalid initialize params");
        //初始化权限
        __AccessControl_init();
        //初始化UUPS升级合约
        __UUPSUpgradeable_init();
        //初始化暂停
        __Pausable_init();
        //给合约部署者分配超管、升级权限
        _grantRole(ADMIN_ROLE,msg.sender);
        _grantRole(UPGRADE_ROLE,msg.sender);

        rewardToken = _rewardToken;
        startBlock = _startBlock;
        endBlock = _endBlock;

        peaceTokenPreBlock = _peaceTokenPreBlock;
    }

    // 升级进行授权
    function _authorizeUpgrade(address newImplementation) internal onlyRole(UPGRADE_ROLE) override {

    }

    /**
    *添加和更新质押池
    *输入参数: 质押代币地址(_stTokenAddress)，池权重(_poolWeight)，最小质押金额(_minDepositAmount)，解除质押锁定区(_unstakeLockedBlocks)。
    *前置条件: 只有管理员可操作。
    *后置条件: 创建新的质押池或更新现有池的配置。
    *异常处理: 权限验证失败或输入数据验证失败。
     */
    function  addPool(address _stTokenAddress,uint256 _poolWeight,uint256 _minDepositAmount,uint256 _unstakeLockedBlocks,bool _isUpdate) public onlyRole(ADMIN_ROLE) {
        //默认池子第一个元素为ETH 原生代币池子
        if (pool.length>0){
            require(_stTokenAddress!=address(0x0),"invalid staking token addres");
        }else{
            require(_stTokenAddress==address(0x0),"invalid staking token addres");
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
        totalPoolWeight += _poolWeight;
        
        //防止状态污染，放到池子层，当添加池子时，为每个池子更新为最新的奖励区块高度
        uint256 lastRewardBlock = block.number>startBlock ? block.number : startBlock;


        _pool = Pool({
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
        emit addPool(_stTokenAddress, _poolWeight, lastRewardBlock, _minDepositAmount, _unstakeLockedBlocks);
    }
    //更改池子权重
    function setPoolWeight(uint256 _pid,uint256 _poolWeight,bool isUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid){
        require(_poolWeight > 0,"invalid pool weight");
        if (isUpdate){
            allPoolUpdate();
        }
        emit setPoolWeight(_pid,_poolWeight);
    }
    //更新池子队列中所有池子的状态，包括用户状态，池子状态等
    function allPoolUpdate() public {
        for(uint pid=0;pid<pool.length;pid++){
            updatePool(pid);
        }
    }
    //更新池子
    function updatePool(uint256 _pid) public checkPid(_pid) {
        Pool storage pool_ = pool[_pid];
        //检查池子是否已经开始计算奖励
        if (pool_.lastRewardBlock >= block.number) {
            //池子未开始计算奖励，直接return
            return;
        }
        //计算出当前更新池子时，当前这个池子在总池子的出快高度，用于计算总出块奖励，
        // 总出块的奖励也包含了其他池子的奖励，需要使用权重获取当前池子应得奖励
        /**
        *不同池子的 lastRewardBlock 可能不同
        *Pool 1: lastRewardBlock = 1000
        *Pool 2: lastRewardBlock = 1050  
        *Pool 3: lastRewardBlock = 1100

        *当 block.number = 1200 时，不同池子计算的区间不同
        *Pool 1: 1000 → 1200 = 200 blocks
        *Pool 2: 1050 → 1200 = 150 blocks  
        *Pool 3: 1100 → 1200 = 100 blocks
        
         */
        uint256 multiplier = block.number - pool_.lastRewardBlock;
        //计算总池子出块所获的的奖励rewardTotalTokenAllPool
        (bool success1,uint256 rewardTotalTokenAllPool) = multiplier.tryMul(peaceTokenPreBlock);
        require(success1,"overflow");
        //计算当前池子占奖励的权重
        (bool success2,uint256 rewardTotalTokenWeight) = rewardTotalTokenAllPool.tryMul(pool_.poolWeight);
        //计算当前池子获取的总奖励PeaceToken数量
        (bool success3,uint256 rewardTotalTokenPrePool) = rewardTotalTokenWeight.tryDiv(totalPoolWeight);
        // 将缓存在内存，不用每次都要从storage中读取，节省gas费用
        uint256 stSupply = pool_.stTokenAmount;
        if (stSupply > 0) {
            //换算奖励代币的单位，金额 = 代币个数 * decimal
            require(rewardToken.decimals()>0,"rewardToken decimal invalid");
            (bool success1,uint256 totalRewardTokenAmount) = rewardTotalTokenPrePool.tryMul(rewardToken.decimals());
            require(success1, "overflow");
            //换算用户accPeaceTokenPreST，获得的Peace Token奖励
            (bool success2,uint245 totalRewardTokenPreStTokenAmount) = totalRewardTokenAmount.tryDiv(stSupply);
            require(success2, "overflow");
            //累加用户质押的每个代币，获得的Peace Token奖励数,用户计算用户每个代币的提取奖励
            (bool success3, uint256 accPeaceTokenPreST) = pool_.accPeaceTokenPreST.tryAdd(totalRewardTokenPreStTokenAmount);
            require(success3, "overflow");

        }
        //池子的奖励金额进行累加：
        pool_.accMetaNodePerST = accMetaNodePreST;
        emit UpdatePool(_pid,pool_.lastRewardBlock,accPeaceTokenPreST);
        
        
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
        _deposit(_pid, _amount);

    }

    function deposit(uint256 _pid,uint256 _amount) public whenNotPaused() checkPid(_pid){
        require(_pid!=0,"current deposit function not support ETH staking,please use depositETH!");
        Pool storage pool_ = pool[_pid];
        require(_amount>pool_.minDepositAmount,"deposit amount is too small");

        if (_amount>0) {
            IERC20(pool_.stTokenAddress).saferTransferFrom(msg.sender,address(this),_amount);
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
            (bool success1,uint256 accST) = accST.tryDiv(rewardToken.decimals());
            require(success1,"accST div rewardTokenDecimals overflow");
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
            (bool success,uint256 _pendingPeace) = user_.stAmount.tryAdd(_amount);
        }
        //更新池子状态 - 质押代币数量
        (bool success5,uint256 _stTokenAmount) = pool_.stTokenAmount.tryAdd(_amount);
        require(success5, "pool stTokenAmount overflow");
        pool_.stTokenAmount = _stTokenAmount;

        //更新用户状态 - 领取代币奖励的数量
        (bool success6,uint256 finishedPeaceToken) = user_.stAmount.tryMul(pool_.accPeaceTokenPerST);
        require(success6,"user stAmount mul accMetaNodePerST overflow");
        //换算成数量
        (success6,finishedPeaceToken) = finishedPeaceToken.tryDiv(rewardToken.decimals());
        require(success6, "finishedMetaNode div 1 ether overflow");

        user_.finishedPeaceToken = finishedPeaceToken;
        emit Deposit(mst.sender, _pid, _amount);

    }

    /**
    *领取奖励
    *输入参数: 池 ID(_pid)。
    *前置条件: 有可领取的奖励。
    *后置条件: 用户领取其奖励，清除已领取的奖励记录。
    *异常处理: 如果没有可领取的奖励，不执行任何操作。
    */
    //

    //提取奖励，提取前需要添加暂停功能
    function claim(uint256 _pid) public whenNotPaused checkPid(_pid) whenNotClaimPaused(){

    } 




}