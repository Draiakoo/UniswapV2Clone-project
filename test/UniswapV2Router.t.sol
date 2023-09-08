// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {UniswapV2Router} from "../src/UniswapV2Router.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {ERC20Mintable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Mintable.sol";


contract UniswapV2RouterTest is Test {

    address public minter = makeAddr("minter");
    address public swapper = makeAddr("swapper");
    address public pirate = makeAddr("pirate");

    UniswapV2Factory public factory;
    UniswapV2Router public router;
    ERC20Mintable public token0;
    ERC20Mintable public token1;
    ERC20Mintable public token2;
    ERC20Mintable public token3;
    ERC20Mintable public token4;
    

    function setUp() public {
        factory = new UniswapV2Factory();
        router = new UniswapV2Router(address(factory));

        token0 = new ERC20Mintable("Token 0", "T0");
        token1 = new ERC20Mintable("Token 1", "T1");
        token2 = new ERC20Mintable("Token 2", "T2");
        token3 = new ERC20Mintable("Token 3", "T3");

        token0.mint(minter, 100 ether);
        token1.mint(minter, 200 ether);
        token2.mint(minter, 200 ether);
        token3.mint(minter, 100 ether);

        factory.createPair(address(token0), address(token1));
        factory.createPair(address(token1), address(token2));

        vm.startPrank(minter);
        token0.approve(address(router), 100 ether);
        token1.approve(address(router), 100 ether);
        router.addLiquidity(address(token0), address(token1), 100 ether, 100 ether, 100 ether, 100 ether, minter, block.timestamp);
        token1.approve(address(router), 100 ether);
        token2.approve(address(router), 100 ether);
        router.addLiquidity(address(token1), address(token2), 100 ether, 100 ether, 100 ether, 100 ether, minter, block.timestamp);
        vm.stopPrank();
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////     Add Liquidity tests     /////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testAddLiquidityDeadlineExpired() public {
        skip(10 days);
        vm.startPrank(minter);
        token0.approve(address(router), 100 ether);
        token1.approve(address(router), 100 ether);
        vm.expectRevert(UniswapV2Router.ExpiredDeadline.selector);
        router.addLiquidity(address(token0), address(token1), 100 ether, 100 ether, 100 ether, 100 ether, minter, block.timestamp-10);
        vm.stopPrank();
    }

    function testAddLiquidityInsufficientToken1() public {
        token0.mint(minter, 100 ether);
        token1.mint(minter, 100 ether);

        // A frontrun bot swap big amount of money
        vm.startPrank(swapper);
        token1.mint(swapper, 50 ether);
        token1.approve(address(router), 50 ether);
        address[] memory path = new address[](2);
        path[0] = address(token1);
        path[1] = address(token0);
        router.swapExactTokensForTokens(50 ether, 0, path, swapper, block.timestamp);
        vm.stopPrank();


        // Minter saw reserves as 100*10**18 token0 and 100*10**18 token1, but got frontrunned
        vm.startPrank(minter);
        token0.approve(address(router), 100 ether);
        token1.approve(address(router), 100 ether);
        vm.expectRevert(UniswapV2Router.Insufficient1Token.selector);
        router.addLiquidity(address(token0), address(token1), 100 ether, 100 ether, 100 ether, 100 ether, minter, block.timestamp);
        vm.stopPrank();
    }

    function testAddLiquidityInsufficientToken0() public {
        token0.mint(minter, 100 ether);
        token1.mint(minter, 100 ether);

        // A frontrun bot swap big amount of money
        vm.startPrank(swapper);
        token0.mint(swapper, 50 ether);
        token0.approve(address(router), 50 ether);
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);
        router.swapExactTokensForTokens(50 ether, 0, path, swapper, block.timestamp);
        vm.stopPrank();


        // Minter saw reserves as 100*10**18 token0 and 100*10**18 token1, but got frontrunned
        vm.startPrank(minter);
        token0.approve(address(router), 100 ether);
        token1.approve(address(router), 100 ether);
        vm.expectRevert(UniswapV2Router.Insufficient0Token.selector);
        router.addLiquidity(address(token0), address(token1), 100 ether, 100 ether, 100 ether, 100 ether, minter, block.timestamp);
        vm.stopPrank();
    }

    function testAddLiquidityFailedSafeTransferFrom() public {
        vm.startPrank(minter);
        vm.expectRevert(UniswapV2Router.TokenTransferFailed.selector);
        router.addLiquidity(address(token0), address(token1), 100 ether, 100 ether, 100 ether, 100 ether, minter, block.timestamp);
        vm.stopPrank();
    }

    function testAddLiquidityCreatePair() public {
        assertEq(factory.pairs(address(token2), address(token3)), address(0));

        token2.mint(minter, 100 ether);
        token3.mint(minter, 100 ether);

        vm.startPrank(minter);
        token2.approve(address(router), 100 ether);
        token3.approve(address(router), 100 ether);
        router.addLiquidity(address(token2), address(token3), 100 ether, 100 ether, 100 ether, 100 ether, minter, block.timestamp);
        vm.stopPrank();

        assertNotEq(factory.pairs(address(token2), address(token3)), address(0));
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    //////////////////////////////////////     Burn Liquidity tests     /////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testBurnLiquidityNonExistingPair() public {
        vm.startPrank(minter);
        vm.expectRevert(UniswapV2Router.NonExistingPair.selector);
        router.burnLiquidity(address(token2), address(token3), 100 ether, 100 ether, 100 ether, minter, block.timestamp);
        vm.stopPrank();
    }

    function testBurnLiquidityNotEnoughToken0Received() public {
        // People has swaped and price of token0 raised
        vm.startPrank(swapper);
        token1.mint(swapper, 50 ether);
        token1.approve(address(router), 50 ether);
        address[] memory path = new address[](2);
        path[0] = address(token1);
        path[1] = address(token0);
        router.swapExactTokensForTokens(50 ether, 0, path, swapper, block.timestamp);
        vm.stopPrank();

        address pairAddress = factory.pairs(address(token0), address(token1));
        vm.startPrank(minter);
        UniswapV2Pair(pairAddress).approve(address(router), 100 ether - 1000);
        vm.expectRevert(UniswapV2Router.NotEnoughToken0Received.selector);
        router.burnLiquidity(address(token0), address(token1), 100 ether - 1000, 100 ether - 1000, 100 ether - 1000, minter, block.timestamp);
        vm.stopPrank();
    }

    function testBurnLiquidityNotEnoughToken1Received() public {
        // People has swaped and price of token1 raised
        vm.startPrank(swapper);
        token0.mint(swapper, 50 ether);
        token0.approve(address(router), 50 ether);
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);
        router.swapExactTokensForTokens(50 ether, 0, path, swapper, block.timestamp);
        vm.stopPrank();

        address pairAddress = factory.pairs(address(token0), address(token1));
        vm.startPrank(minter);
        UniswapV2Pair(pairAddress).approve(address(router), 100 ether - 1000);
        vm.expectRevert(UniswapV2Router.NotEnoughToken1Received.selector);
        router.burnLiquidity(address(token0), address(token1), 100 ether - 1000, 100 ether - 1000, 100 ether - 1000, minter, block.timestamp);
        vm.stopPrank();
    }

    function testBurnLiquiditySuccess() public {
        address pairAddress = factory.pairs(address(token0), address(token1));

        vm.startPrank(minter);
        UniswapV2Pair(pairAddress).approve(address(router), 100 ether - 1000);
        (uint256 amount0, uint256 amount1) = router.burnLiquidity(address(token0), address(token1), 100 ether - 1000, 100 ether - 1000, 100 ether - 1000, minter, block.timestamp);
        vm.stopPrank();

        assertEq(amount0, token0.balanceOf(minter));
        assertEq(amount1, token1.balanceOf(minter));
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////     Swap exact tokens for tokens tests     //////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testSwapExactTokensForTokensAmountRequirementNotMetSlippage() public {
        // A frontrun bot buys a big amount before user's trade and get far less tokens
        vm.startPrank(pirate);
        token0.mint(pirate, 50 ether);
        token0.approve(address(router), 50 ether);
        address[] memory path1 = new address[](2);
        path1[0] = address(token0);
        path1[1] = address(token1);
        router.swapExactTokensForTokens(50 ether, 0, path1, pirate, block.timestamp);
        vm.stopPrank();
        
        vm.startPrank(swapper);
        token0.mint(swapper, 1 ether);
        token0.approve(address(router), 1 ether);
        address[] memory path2 = new address[](2);
        path2[0] = address(token0);
        path2[1] = address(token1);
        vm.expectRevert(UniswapV2Router.AmountRequirementNotMet.selector);
        router.swapExactTokensForTokens(1 ether, 0.9 ether, path2, swapper, block.timestamp);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokensSimpleSwap() public {
        token0.mint(swapper, 1 ether);
        
        vm.startPrank(swapper);
        token0.approve(address(router), 1 ether);
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);
        router.swapExactTokensForTokens(1 ether, 0.98 ether, path, swapper, block.timestamp);
        vm.stopPrank();

        assertGt(token1.balanceOf(swapper), 0.98 ether);
    }

    function testSwapExactTokensForTokensMultiSwap() public {
        token0.mint(swapper, 1 ether);
        
        vm.startPrank(swapper);
        token0.approve(address(router), 1 ether);
        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(token2);
        router.swapExactTokensForTokens(1 ether, 0.97 ether, path, swapper, block.timestamp);
        vm.stopPrank();

        assertGt(token2.balanceOf(swapper), 0.97 ether);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////     Swap tokens for exact tokens tests     //////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testSwapTokensForExactTokensAmountRequirementNotMetSlippage() public {
        // A frontrun bot buys a big amount before user's trade and needs far more tokens to get his 1*10**18 token 1 out
        vm.startPrank(pirate);
        token0.mint(pirate, 50 ether);
        token0.approve(address(router), 50 ether);
        address[] memory path1 = new address[](2);
        path1[0] = address(token0);
        path1[1] = address(token1);
        router.swapExactTokensForTokens(50 ether, 0, path1, pirate, block.timestamp);
        vm.stopPrank();
        
        vm.startPrank(swapper);
        token0.mint(swapper, 1.1 ether);
        token0.approve(address(router), 1.1 ether);
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);
        vm.expectRevert(UniswapV2Router.AmountRequirementNotMet.selector);
        router.swapTokensForExactTokens(1 ether, 1.1 ether, path, swapper, block.timestamp);
        vm.stopPrank();
    }

    function testSwapTokensForExactTokensSimpleSwap() public {
        token0.mint(swapper, 1.04 ether);
        
        vm.startPrank(swapper);
        token0.approve(address(router), 1.04 ether);
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);
        router.swapTokensForExactTokens(1 ether, 1.04 ether, path, swapper, block.timestamp);
        vm.stopPrank();
    }

    function testSwapTokensForExactTokensMultiSwap() public {
        token0.mint(swapper, 1.05 ether);
        
        vm.startPrank(swapper);
        token0.approve(address(router), 1.05 ether);
        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(token2);
        router.swapTokensForExactTokens(1 ether, 1.05 ether, path, swapper, block.timestamp);
        vm.stopPrank();
    }
}
