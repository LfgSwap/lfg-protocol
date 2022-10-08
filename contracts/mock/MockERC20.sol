// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract MockERC20 is ERC20, Ownable {
    uint256 private constant preMineSupply = 20000000000 * 1e18;

    constructor(
        string memory name, 
        string memory symbol
    ) public ERC20(name, symbol) {
        
        _mint(msg.sender, preMineSupply);
    }

    function mint(address user, uint256 _amount) public onlyOwner {
         _mint(user, _amount);
    }

    function setDecimal(uint8 _decimals) external onlyOwner {
        _setupDecimals(_decimals);    
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        // console.log("transferFrom-");
        // console.log("transferFrom.sender", msg.sender);
        // console.log("transferFrom-", tx.origin);
        // console.logBytes(msg.data);
        // console.logBytes4(msg.sig);
        
        return super.transferFrom( sender, recipient, amount);
    }
}

