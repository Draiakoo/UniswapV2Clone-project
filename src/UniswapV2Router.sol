// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {UniswapV2Factory} from "./UniswapV2Factory.sol";
import {UniswapV2Pair} from "./UniswapV2Pair.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {Math} from "./libraries/Math.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract UniswapV2Router {
    using UniswapV2Library for uint256;

    error ExpiredDeadline();
    error TokenTransferFailed();
    error Insufficient0Token();
    error Insufficient1Token();
    error NonExistingPair();
    error NotEnoughToken0Received();
    error NotEnoughToken1Received();
    error AmountRequirementNotMet();
    
    UniswapV2Factory public immutable factory;

    bytes4 public constant TRANSFERFROMSELECTOR = bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));
    bytes4 public constant TRANSFERSELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    constructor(address _factory){
        factory = UniswapV2Factory(_factory);
    }

    modifier notExpiredDeadline(uint256 deadline){
        if(deadline < block.timestamp){
            revert ExpiredDeadline();
        }
        _;
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFERFROMSELECTOR, from, to, amount));
        if (!(success && (data.length==0 || abi.decode(data, (bool))))) {
            revert TokenTransferFailed();
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(TRANSFERSELECTOR, to, amount));
        if(!(success && (data.length==0 || abi.decode(data, (bool))))){
            revert TokenTransferFailed();
        }
    }

    function addLiquidity(
        address token0,
        address token1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline) 
    external notExpiredDeadline(deadline) returns(uint amount0, uint amount1, uint liquidity){
        address pairAddress;
        if(factory.pairs(token0, token1) == address(0)){
            pairAddress = factory.createPair(token0, token1);
            (amount0, amount1) = (amount0Desired, amount1Desired);
        } else {
            pairAddress = UniswapV2Library.computePairAddress(token0, token1, address(factory));
        }
        (uint112 reserve0, uint112 reserve1) = UniswapV2Pair(pairAddress).getReserves();
        if (reserve0 == 0 && reserve1 == 0) {
            (amount0, amount1) = (amount0Desired, amount1Desired);
        } else {
            uint256 optimal1Amount = UniswapV2Library.quoteMintLiquidity(reserve0, reserve1, amount0Desired);
            if(optimal1Amount <= amount1Desired){
                if(optimal1Amount < amount1Min){
                    revert Insufficient1Token();
                }
                (amount0, amount1) = (amount0Desired, amount1Desired);
            } else {
                uint256 optimal0Amount = UniswapV2Library.quoteMintLiquidity(reserve1, reserve0, amount1Desired);
                if(optimal0Amount < amount0Min){
                    revert Insufficient0Token();
                }
                (amount0, amount1) = (optimal0Amount, amount1Desired);
            }
        }
        _safeTransferFrom(token0, msg.sender, pairAddress, amount0);
        _safeTransferFrom(token1, msg.sender, pairAddress, amount1);
        liquidity = UniswapV2Pair(pairAddress).mint(to);
    }

    function burnLiquidity(
        address token0,
        address token1,
        uint liquidity,
        uint amount0Min,
        uint amount1Min,
        address to,
        uint deadline)
    external notExpiredDeadline(deadline) returns(uint256 amount0, uint256 amount1){
        address pairAddress = factory.pairs(token0, token1);
        if(pairAddress == address(0)){
            revert NonExistingPair();
        }
        _safeTransferFrom(address(pairAddress), msg.sender, address(pairAddress), liquidity);
        (uint256 amount0Transfered, uint256 amount1Transfered) = UniswapV2Pair(pairAddress).burn(to);
        (amount0, amount1) = token0 > token1 ? (amount1Transfered, amount0Transfered) : (amount0Transfered, amount1Transfered);
        if(amount0 < amount0Min){
            revert NotEnoughToken0Received();
        }
        if(amount1 < amount1Min){
            revert NotEnoughToken1Received();
        }
    }

    function _swap(uint256[] memory amounts, address[] memory path, address receiver) private {
        uint256 length = amounts.length;
        _safeTransferFrom(path[0], msg.sender, address(this), amounts[0]);
        for(uint256 i; i < length - 1;){
            address pairAddress = factory.pairs(path[i], path[i+1]);
            (uint256 amount0Out, uint256 amount1Out) = path[i] > path[i+1] ? (amounts[i+1], uint256(0)) : (uint256(0), amounts[i+1]);
            _safeTransfer(path[i], pairAddress, amounts[i]);
            UniswapV2Pair(pairAddress).swap(amount0Out, amount1Out, address(this));
            unchecked{
                ++i;
            }
        }
        _safeTransfer(path[length-1], receiver, amounts[length-1]);
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline)
    external notExpiredDeadline(deadline) returns (uint256[] memory amounts){
        amounts = UniswapV2Library.getAmountsOut(address(factory), amountIn, path);
        if(amounts[amounts.length-1] < amountOutMin){
            revert AmountRequirementNotMet();
        }
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline)
    external notExpiredDeadline(deadline) returns (uint256[] memory amounts) {
        amounts = UniswapV2Library.getAmountsIn(address(factory), amountOut, path);
        if(amounts[0] > amountInMax){
            revert AmountRequirementNotMet();
        }
        _swap(amounts, path, to);
    }
}