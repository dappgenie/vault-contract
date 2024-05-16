// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { ITradingContract } from "./ITrade.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

address constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;


contract TradingContract is ITradingContract {
    ISwapRouter private constant router = ISwapRouter(SWAP_ROUTER);
    // Function to swap `amountIn` of one token for as much as possible of another token
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address recipient,
        uint24 poolFee
    )
        external
        returns (uint256 amountOut)
    {
        // Transfer the specified amount of `tokenIn` to this contract.
        TransferHelper.safeTransferFrom(tokenIn, recipient, address(this), amountIn);

        // Approve the router to spend the specified amount of `tokenIn`.
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

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
        amountOut = router.exactInputSingle(params);
    }
}
