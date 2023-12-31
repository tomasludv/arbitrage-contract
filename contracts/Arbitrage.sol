// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IQuickswapRouter} from "../interfaces/IQuickswapRouter.sol";
import {IUniswapRouter} from "../interfaces/IUniswapRouter.sol";
import {IPearlRouter} from "../interfaces/IPearlRouter.sol";
import {IKyberswapRouter} from "../interfaces/IKyberswapRouter.sol";

error InvalidAction(Action action);
error AmountOutMinNotReached(uint256 amountOut, uint256 amountOutMin);

enum Action {
    UNISWAP,
    PEARL,
    QUICKSWAP,
    RETRO,
    KYBERSWAP
}

contract Arbitrage is Ownable {
    address private constant uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant quickswapRouter = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
    address private constant pearlRouter = 0xcC25C0FD84737F44a7d38649b69491BBf0c7f083;
    address private constant retroRouter = 0x1891783cb3497Fdad1F25C933225243c2c7c4102;
    address private constant kyberswapRouter = 0xF9c2b5746c946EF883ab2660BbbB1f10A5bdeAb4;

    constructor() Ownable(msg.sender) {}

    function withdraw(address token) external onlyOwner {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function arb(address tokenIn, uint256 amountIn, uint256 amountOutMin, bytes memory data) external onlyOwner returns (uint256 amountOut) {
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        amountOut = amountIn;

        while (data.length > 0) {
            (, Action action) = abi.decode(data, (bytes, Action));
            if (action == Action.UNISWAP) {
                amountOut = uniswap(amountOut, data);
            } else if (action == Action.RETRO) {
                amountOut = retro(amountOut, data);
            } else if (action == Action.PEARL) {
                amountOut = pearl(amountOut, data);
            } else if (action == Action.QUICKSWAP) {
                amountOut = quickswap(amountOut, data);
            } else if (action == Action.KYBERSWAP) {
                amountOut = kyberswap(amountOut, data);
            } else {
                revert InvalidAction(action);
            }

            (data) = abi.decode(data, (bytes));
        }

        if (amountOut < amountOutMin) {
            revert AmountOutMinNotReached(amountOut, amountOutMin);
        }

        IERC20(tokenIn).transfer(msg.sender, amountOut);
    }

    function uniswap(uint256 amountIn, bytes memory data) internal returns (uint256 amountOut) {
        (, , address tokenIn, address tokenOut, uint24 fee) = abi.decode(data, (bytes, Action, address, address, uint24));
        IERC20(tokenIn).approve(uniswapRouter, amountIn);
        amountOut = IUniswapRouter(uniswapRouter).exactInputSingle(
            IUniswapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function kyberswap(uint256 amountIn, bytes memory data) internal returns (uint256 amountOut) {
        (, , address tokenIn, address tokenOut, uint24 fee) = abi.decode(data, (bytes, Action, address, address, uint24));
        IERC20(tokenIn).approve(kyberswapRouter, amountIn);
        amountOut = IKyberswapRouter(kyberswapRouter).swapExactInputSingle(
            IKyberswapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                minAmountOut: 0,
                limitSqrtP: 0
            })
        );
    }

    function retro(uint256 amountIn, bytes memory data) internal returns (uint256 amountOut) {
        (, , address tokenIn, address tokenOut, uint24 fee) = abi.decode(data, (bytes, Action, address, address, uint24));
        IERC20(tokenIn).approve(retroRouter, amountIn);
        amountOut = IUniswapRouter(retroRouter).exactInputSingle(
            IUniswapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function quickswap(uint256 amountIn, bytes memory data) internal returns (uint amountOut) {
        (, , address tokenIn, address tokenOut) = abi.decode(data, (bytes, Action, address, address));
        IERC20(tokenIn).approve(quickswapRouter, amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint[] memory amounts = IQuickswapRouter(quickswapRouter).swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            path: path,
            to: address(this),
            deadline: block.timestamp
        });
        amountOut = amounts[amounts.length - 1];
    }

    function pearl(uint256 amountIn, bytes memory data) internal returns (uint256 amountOut) {
        (, , address tokenIn, address tokenOut, bool stable) = abi.decode(data, (bytes, Action, address, address, bool));
        IERC20(tokenIn).approve(pearlRouter, amountIn);
        uint256[] memory amounts = IPearlRouter(pearlRouter).swapExactTokensForTokensSimple({
            amountIn: amountIn,
            amountOutMin: 0,
            tokenFrom: tokenIn,
            tokenTo: tokenOut,
            stable: stable,
            to: address(this),
            deadline: block.timestamp
        });
        amountOut = amounts[amounts.length - 1];
    }
}
