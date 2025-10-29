pragma solidity ^0.8;
// 奖励代币,用于发行奖励
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

contract PeaceToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("PeaceToken","PTN"){
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply * (10 ** 18));
        }
    }
    function getDecimals() public view virtual returns (uint8) {
        return decimals();
    }
}
