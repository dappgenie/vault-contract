// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

interface ITradingContract {
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address recipient,
        uint8 poolFee
    )
        external
        returns (uint256 amountOut);
}
