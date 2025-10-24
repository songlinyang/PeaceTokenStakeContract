pragma solidity ^0.8;
// 奖励代币,用于发行奖励
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

contract PeaceToken is ERC20 {
    uint8 private _decimals; // 代币单位

    constructor(uint256 initialSupply) ERC20("PeaceToken","PTN"){
        _decimals = 18;
        if (initialSupply > 0) {
            _mint(msg.sender, initialSupply * (10 ** uint256(_decimals)));
        }
    }
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}