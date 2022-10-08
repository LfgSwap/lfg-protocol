// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import {IERC20 as SIERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILfgToken is SIERC20 {
    function mint(address to, uint256 amount) external returns (bool);
}
