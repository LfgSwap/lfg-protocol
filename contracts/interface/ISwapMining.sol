// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

interface ISwapMining {
  function swap(address _sender, address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _amountOut) external returns (bool);
}
