// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {ERC20Mintable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Mintable.sol";
import {UniswapV2Library} from "../src/libraries/UniswapV2Library.sol";
import {Math} from "../src/libraries/Math.sol";

contract UniswapV2PairTest is Test {
    using Math for uint256;
    using UniswapV2Library for uint256;

    ERC20Mintable public token0;
    ERC20Mintable public token1;

    UniswapV2Pair public pair;

    address public minter = makeAddr("minter");
    address public swapper = makeAddr("swapper");
    address public pirate = makeAddr("pirate");

    function setUp() public {
        token0 = ERC20Mintable(new ERC20Mintable("Token 0", "T0"));
        token1 = ERC20Mintable(new ERC20Mintable("Token 1", "T1"));

        pair = UniswapV2Pair(new UniswapV2Pair(address(token0), address(token1)));
    }

    modifier addInitialLiquidity() {
        uint256 token0ToMint = 100 ether;
        uint256 token1ToMint = 100 ether;

        token0.mint(minter, token0ToMint);
        token1.mint(minter, token1ToMint);

        vm.startPrank(minter);
        token0.transfer(address(pair), token0ToMint);
        token1.transfer(address(pair), token1ToMint);

        pair.mint(minter);
        vm.stopPrank();
        _;
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////     Mint tests     //////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testMintLiquidityNoInitialLiquidity() public {
        uint256 token0ToMint = 100 ether;
        uint256 token1ToMint = 100 ether;

        token0.mint(minter, token0ToMint);
        token1.mint(minter, token1ToMint);

        vm.startPrank(minter);
        token0.transfer(address(pair), token0ToMint);
        token1.transfer(address(pair), token1ToMint);

        uint256 lpTokensMinted = pair.mint(minter);
        vm.stopPrank();

        assertEq(1000, pair.balanceOf(address(0)));
        assertEq(lpTokensMinted, (Math.sqrt(token0ToMint * token0ToMint)) - 1000);
        assertEq(lpTokensMinted, pair.balanceOf(minter));
    }

    function testMintLiquidityInitialLiquidity() public {
        uint256 token0ToMint = 100 ether;
        uint256 token1ToMint = 100 ether;

        token0.mint(minter, token0ToMint * 2);
        token1.mint(minter, token1ToMint * 2);

        vm.startPrank(minter);
        token0.transfer(address(pair), token0ToMint);
        token1.transfer(address(pair), token1ToMint);
        pair.mint(minter);
        vm.stopPrank();

        vm.startPrank(minter);
        token0.transfer(address(pair), token0ToMint);
        token1.transfer(address(pair), token1ToMint);
        pair.mint(minter);
        vm.stopPrank();

        assertEq(1000, pair.balanceOf(address(0)));
        assertEq(pair.balanceOf(minter), token0ToMint * 2 - 1000);
    }

    function testNoTokensToMint() public {
        uint256 token0ToMint = 100 ether;
        uint256 token1ToMint = 100 ether;

        token0.mint(minter, token0ToMint);
        token1.mint(minter, token1ToMint);

        vm.startPrank(minter);
        token0.transfer(address(pair), token0ToMint);
        token1.transfer(address(pair), token1ToMint);
        pair.mint(minter);
        vm.stopPrank();

        vm.expectRevert(UniswapV2Pair.NoLPTokensToMint.selector);
        pair.mint(minter);
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////     Burn tests     //////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testBurnNoLPTokensTransfered() public addInitialLiquidity(){
        vm.expectRevert(UniswapV2Pair.NoTokenToTransfer.selector);
        vm.prank(minter);
        pair.burn(minter);
    }

    function testBurnSuccessful() public addInitialLiquidity(){
        uint256 expectTokenAmount = 100 ether - 1000;
        vm.startPrank(minter);
        pair.transfer(address(pair), pair.balanceOf(minter));
        (uint256 token0Redeemed, uint256 token1Redeemed) = pair.burn(minter);
        vm.stopPrank();

        assertEq(token0Redeemed, expectTokenAmount);
        assertEq(token1Redeemed, expectTokenAmount);
    }

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////////////////     Burn tests     //////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function testSwapNoTokenToGet() public {
        vm.expectRevert(UniswapV2Pair.NoTokensToSwap.selector);
        vm.startPrank(swapper);
        pair.swap(0, 0, swapper);
        vm.stopPrank();
    }

    function testSwapNoSuficientLiquidity() public addInitialLiquidity(){
        token0.mint(swapper, 200 ether);

        vm.startPrank(swapper);
        token0.transfer(address(pair), 200 ether);
        vm.expectRevert(UniswapV2Pair.NotEnoughLiquidityToSwap.selector);
        pair.swap(0, 200 ether, swapper);
        vm.stopPrank();
    }

    function testNoTokensSent() public addInitialLiquidity{
        vm.startPrank(swapper);
        vm.expectRevert(UniswapV2Pair.NoTokensGivenToSwap.selector);
        pair.swap(0, 50 ether, swapper);
        vm.stopPrank();
    }

    function testKDropped() public addInitialLiquidity{
        token0.mint(swapper, 90 ether);

        vm.startPrank(swapper);
        token0.transfer(address(pair), 90 ether);
        vm.expectRevert(UniswapV2Pair.KDropped.selector);
        pair.swap(0, 90 ether, swapper);
        vm.stopPrank();
    }

    function testSuccessfulSwap() public addInitialLiquidity{
        token0.mint(swapper, 90 ether);
        (uint112 reserve0, uint112 reserve1) = pair.getReserves();
        uint256 amount1Out = UniswapV2Library.getAmountOut(reserve0, reserve1, 90 ether);
        vm.startPrank(swapper);
        token0.transfer(address(pair), 90 ether);
        pair.swap(0, amount1Out, swapper);
        assertEq(amount1Out, token1.balanceOf(swapper));
    }


    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////     Vulnerabilities     ///////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////


    // Figured out that since the lp tokens to distribute are calculated with the current reserves, a user can not take fees
    // that have not generated with his capital
    function testFeesAccumulatedMintLiquidityAndBurnToObtainFees() public {
        uint256 token0ToMintMinter = 100 ether;
        uint256 token1ToMintMinter = 100 ether;

        uint256 token0ToSwapSwapper = 100 ether;

        uint256 token0ToMintPirate = 3334 ether;
        uint256 token1ToMintPirate = 1000 ether;

        token0.mint(minter, token0ToMintMinter);
        token1.mint(minter, token1ToMintMinter);

        token0.mint(swapper, token0ToSwapSwapper);

        token0.mint(pirate, token0ToMintPirate);
        token1.mint(pirate, token1ToMintPirate);

        vm.startPrank(minter);
        token0.transfer(address(pair), token0ToMintMinter);
        token1.transfer(address(pair), token1ToMintMinter);
        pair.mint(minter);
        vm.stopPrank();

        vm.startPrank(swapper);
        token0.transfer(address(pair), token0ToSwapSwapper);
        pair.swap(0, 40 ether, swapper);
        vm.stopPrank();

        (uint112 reserve0, uint112 reserve1) = pair.getReserves();
        assertEq(reserve0, 200 ether);
        assertEq(reserve1, 60 ether);

        uint256 pirateBalanceBeforeToken0 = token0.balanceOf(pirate);
        uint256 pirateBalanceBeforeToken1 = token1.balanceOf(pirate);
        vm.startPrank(pirate);
        token0.transfer(address(pair), token0ToMintPirate);
        token1.transfer(address(pair), token1ToMintPirate);
        pair.mint(pirate);
        pair.transfer(address(pair), pair.balanceOf(pirate));
        pair.burn(pirate);
        vm.stopPrank();
        uint256 pirateBalanceAfterToken0 = token0.balanceOf(pirate);
        uint256 pirateBalanceAfterToken1 = token1.balanceOf(pirate);

        assertLt(pirateBalanceAfterToken0, pirateBalanceBeforeToken0);
        assertLt(pirateBalanceAfterToken1, pirateBalanceBeforeToken1);
    }

}
