// SPDX-License-Identifier

pragma solidity 0.8.20;

import {UniswapV2Pair} from "./UniswapV2Pair.sol";

contract UniswapV2Factory {

    error MustBeDifferentTokens();
    error TokenWithZeroAddress();
    error PairAlreadyExisting();
    error PairDeploymentFailed();

    event PoolCreated(address token0, address token1, address poolAddress);

    mapping(address token0 => mapping(address token1 => address pairAddress)) public pairs;

    function createPair(address token0, address token1) external returns(address pairAddress){
        if(token0 == token1){
            revert MustBeDifferentTokens();
        }
        (token0, token1) = token0 > token1 ? (token1, token0) : (token0, token1);
        if(token0 == address(0)){
            revert TokenWithZeroAddress();
        }
        if(pairs[token0][token1] != address(0)){
            revert PairAlreadyExisting();
        }
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pairAddress = address(new UniswapV2Pair{salt: salt}(token0, token1));
        pairs[token0][token1] = pairAddress;
        pairs[token1][token0] = pairAddress;

        emit PoolCreated(token0, token1, pairAddress);
    }

}