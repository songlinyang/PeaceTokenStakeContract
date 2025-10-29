pragma solidity ^0.8;

import "./PeaceStake.sol";

contract PeaceStakeFactory{
    address[] public PeaceStakes;

    mapping(uint256 numberID=>PeaceStake) public PeaceStakeMap;

    event PeaceStakeCreated(address indexed PeaceStakesAddress,uint256 tokenId);

    //工厂方法创建一个新的质押
    function createPeaceStake(IERC20 _rewardToken,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _peaceTokenPreBlock,uint256 numberID) external returns (address) {
            PeaceStake pStake= new PeaceStake();
            pStake.initialize(_rewardToken, _startBlock, _endBlock, _peaceTokenPreBlock);
            PeaceStakes.push(address(pStake));
            PeaceStakeMap[numberID]=pStake;

            emit PeaceStakeCreated(address(pStake), numberID);
            return address(pStake);
        }

        function getPeaceStakes() external view returns(address[] memory){
            return PeaceStakes;
        }

        function getPeaceStake(uint256 numberID) external view returns(address){
            require(numberID<PeaceStakes.length,"numberID out of bounds");
            return PeaceStakes[numberID];
        }
}