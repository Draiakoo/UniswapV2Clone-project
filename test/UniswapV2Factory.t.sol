// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {UniswapV2Library} from "../src/libraries/UniswapV2Library.sol";

contract UniswapV2FactoryTest is Test {
    using UniswapV2Library for uint256;

    address public minter = makeAddr("minter");
    address public swapper = makeAddr("swapper");
    address public pirate = makeAddr("pirate");

    address public token0 = makeAddr("token0");
    address public token1 = makeAddr("token1");

    UniswapV2Factory public factory;

    function setUp() public {
        factory = new UniswapV2Factory();
    }

    function testCreatePairSameTokens() public {
        vm.expectRevert(UniswapV2Factory.MustBeDifferentTokens.selector);
        factory.createPair(token0, token0);
    }

    function testCreatePairZeroAddressToken() public {
        vm.expectRevert(UniswapV2Factory.TokenWithZeroAddress.selector);
        factory.createPair(address(0), token0);
    }

    function testCreatePairAlreadyExistingPair() public {
        factory.createPair(token0, token1);
        vm.expectRevert(UniswapV2Factory.PairAlreadyExisting.selector);
        factory.createPair(token0, token1);
    }

    function testCreatePairSuccessful() public {
        address createdPair = factory.createPair(token0, token1);
        address computedPairAddress = UniswapV2Library.computePairAddress(token0, token1, address(factory));
        console.log("Real address: ", createdPair);
        console.log("Computed address: ", computedPairAddress);
        assertEq(createdPair, computedPairAddress);
        assertEq(factory.pairs(token0, token1), createdPair);
        assertEq(factory.pairs(token1, token0), createdPair);
    }
}
