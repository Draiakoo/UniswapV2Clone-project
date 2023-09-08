// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {UniswapV2Pair} from "../UniswapV2Pair.sol";

library UniswapV2Library {

    error SameTokenAddresses();
    error TokenZeroAddress();
    error SomeValueIsZero();
    error InvalidPathAddress();
    
    function _sortTokens(address token0, address token1) public pure returns(address token0Sorted, address token1Sorted){
        if(token0 == token1){
            revert SameTokenAddresses();
        }
        (token0Sorted, token1Sorted) = token0 > token1 ? (token1, token0) : (token0, token1);
        if(token0Sorted == address(0)){
            revert TokenZeroAddress();
        }
    }

    function computePairAddress(address token0, address token1, address factory) public pure returns(address computedAddress){
        (token0, token1) = _sortTokens(token0, token1);
        computedAddress = address(uint160(uint256(bytes32(keccak256(abi.encodePacked(
            bytes1(0xff),
            factory,
            keccak256(abi.encodePacked(token0, token1)),
            keccak256(abi.encodePacked(
                type(UniswapV2Pair).creationCode,
                abi.encode(token0, token1)
            ))
        ))))));
    }

    function quoteMintLiquidity(uint256 reserve0, uint256 reserve1, uint256 amount0) public pure returns(uint256 amount1){
        if(amount0 == 0 || reserve0 == 0 || reserve1 == 0){
            revert SomeValueIsZero();
        }
        amount1 = amount0 * reserve1 / reserve0;
    }

    // Following functions have been derived from the following formula: 
    //              (x + Δx·0.997)·(y - Δy)=x·y
    // Being:
    //  - x: reserveIn
    //  - y: reserveOut
    //  - Δx: amountIn taking into account the 0.3% fee
    //  - Δy: amountOut


    //          y·Δx·0.997
    //  Δy = ----------------
    //          x + Δx·0.997    
    function getAmountOut(uint256 reserveIn, uint256 reserveOut, uint256 amountIn) public pure returns(uint256 amountOut){
        if(amountIn == 0 || reserveIn == 0 || reserveOut == 0){
            revert SomeValueIsZero();
        }
        amountOut = reserveOut*amountIn*997/(reserveIn*1000+amountIn*997);
    }


    //             x·Δy
    //  Δx = ----------------
    //         (y-Δy)·0,997   
    function getAmountIn(uint256 reserveIn, uint256 reserveOut, uint256 amountOut) public pure returns(uint256 amountIn){
        if(amountOut == 0 || reserveIn == 0 || reserveOut == 0){
            revert SomeValueIsZero();
        }
        amountIn = reserveIn*amountOut*1000/((reserveOut-amountOut)*997) + 1;
    }

    // helper functions for multihop swaps

    function _getReserves(address token0, address token1, address factory) private view returns(uint112 reserveA, uint112 reserveB){
        (address tokenA,) = _sortTokens(token0, token1);
        address pairAddress = computePairAddress(token0, token1, factory);
        (uint112 reserve0, uint112 reserve1) = UniswapV2Pair(pairAddress).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) public view returns (uint256[] memory amounts){
        uint256 length = path.length;
        if(length < 2){
            revert InvalidPathAddress();
        }
        amounts = new uint256[](length);
        amounts[0] = amountIn;
        uint112 reserve0;
        uint112 reserve1;
        for(uint256 i; i<length-1;){
            (reserve0, reserve1) = _getReserves(path[i], path[i+1], factory);
            amounts[i+1] = getAmountOut(reserve0, reserve1, amounts[i]);
            unchecked{
                ++i;
            }
        }
    }

    function getAmountsIn(address factory, uint256 amountOut, address[] memory path) public view returns (uint256[] memory amounts){
        uint256 length = path.length;
        if(length < 2){
            revert InvalidPathAddress();
        }
        amounts = new uint256[](length);
        amounts[length - 1] = amountOut;
        uint112 reserve0;
        uint112 reserve1;
        for(uint256 i = length-1; i > 0;){
            (reserve0, reserve1) = _getReserves(path[i-1], path[i], factory);
            amounts[i-1] = getAmountIn(reserve0, reserve1, amounts[i]);
            unchecked{
                --i;
            }
        }
    }
}