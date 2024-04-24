// SPDX-License-Identifier: MIT 
pragma solidity =0.8.25;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol"; 
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ITradingContract} from "./ITrade.sol";


contract TradingContract is ITradingContract {
    ISwapRouter public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = ISwapRouter(_swapRouter);
    }

    // Function to swap `amountIn` of one token for as much as possible of another token
    function swapExactInputSingle(address tokenIn, address tokenOut, uint256 amountIn, address recipient, uint24 poolFee) external returns (uint256 amountOut) {
        // Transfer the specified amount of `tokenIn` to this contract.
        TransferHelper.safeTransferFrom(tokenIn, recipient, address(this), amountIn);

        // Approve the router to spend the specified amount of `tokenIn`.
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);

        // Set the parameters for the swap.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // Execute the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }
}