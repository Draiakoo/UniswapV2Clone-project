// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {Math} from "./libraries/Math.sol";
import {UQ112x112} from "./libraries/UQ112x112.sol";

contract UniswapV2Pair is UniswapV2ERC20{
    using UQ112x112 for uint224;
    using Math for uint256;

    event Mint(address liquidityProvider, uint256 token0Provided, uint256 token1Provided);
    event Sync(uint112 reserve0, uint112 reserve1);
    event Burn(address to, uint256 token0Amount, uint256 token1Amount);
    event Swap(uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out);

    error NotFactory();
    error NoLPTokensToMint();
    error CurrentBalanceOverflow();
    error TransferFailed();
    error NoTokenToTransfer();
    error NoTokensToSwap();
    error NotEnoughLiquidityToSwap();
    error NoTokensGivenToSwap();
    error KDropped();
    error CanNotReenterThisFunction();

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    bytes4 public SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    bool private locked;

    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private lastBlockTimestamp;

    uint256 public price0Cumulative;
    uint256 public price1Cumulative;

    // I am not implementing flash swaps, so I do not need nonReentrant modifier

    // modifier nonReentrant() {
    //     if(locked){
    //         revert CanNotReenterThisFunction();
    //     }
    //     locked = true;
    //     _;
    //     locked = false;
    // }

    constructor(address _token0, address _token1) {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, amount));
        if(!(success && (data.length==0 || abi.decode(data, (bool))))){
            revert TransferFailed();
        }
    }

    function _update(uint256 currentToken0Balance, uint256 currentToken1Balance, uint112 _reserve0, uint112 _reserve1) private {
        if(currentToken0Balance > type(uint112).max || currentToken1Balance > type(uint112).max){
            revert CurrentBalanceOverflow();
        }
        uint32 timestamp = uint32(block.timestamp);
        unchecked {
            uint32 timeElapsed = timestamp - lastBlockTimestamp;
            if(timeElapsed > 0 && _reserve0!=0 && _reserve1!=0){
                price0Cumulative += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
                price1Cumulative += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }    
        }
        reserve0 = uint112(currentToken0Balance);
        reserve1 = uint112(currentToken1Balance);
        lastBlockTimestamp = timestamp;

        emit Sync(reserve0, reserve1);
    }

    // 1. Check one of the 2 amounts to transfer greater than 0
    // 2. Check pool has enough liquidity
    // 3. Transfer tokens
    // 4. Check if user actually deposited one of the 2 tokens
    // 5. Check that new k is greater or equal to last k
    function swap(uint256 amount0Out, uint256 amount1Out, address receiver) external{
        if(amount0Out == 0 && amount1Out == 0){
            revert NoTokensToSwap();
        }
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        if(amount0Out > _reserve0 || amount1Out > _reserve1){
            revert NotEnoughLiquidityToSwap();
        }

        address _token0 = token0;
        address _token1 = token1;

        if(amount0Out > 0) _safeTransfer(_token0, receiver, amount0Out);
        if(amount1Out > 0) _safeTransfer(_token1, receiver, amount1Out);

        uint256 balance0After = IERC20(_token0).balanceOf(address(this));
        uint256 balance1After = IERC20(_token1).balanceOf(address(this));

        uint256 amount0In = balance0After > _reserve0 - amount0Out ? balance0After - (_reserve0 - amount0Out) : 0; 
        uint256 amount1In = balance1After > _reserve1 - amount1Out ? balance1After - (_reserve1 - amount1Out) : 0;

        if(amount0In == 0 && amount1In == 0){
            revert NoTokensGivenToSwap();
        }

        uint256 newK = (balance0After*1000 - amount0In*3) * (balance1After*1000 - amount1In*3);
        
        if(newK < uint256(_reserve0) * uint256(_reserve1) * 1000**2){
            revert KDropped();
        }

        _update(balance0After, balance1After, _reserve0, _reserve1);

        emit Swap(amount0In, amount1In, amount0Out, amount1Out);
    }

    // It has to be sent the both token amounts before calling this function
    function mint(address lpReceiver) external returns(uint256 lpTokensToMint){
        (uint112 _reserve0, uint112 _reserve1) = getReserves();
        
        uint256 currentToken0Balance = IERC20(token0).balanceOf(address(this));
        uint256 currentToken1Balance = IERC20(token1).balanceOf(address(this));

        uint256 token0Received = currentToken0Balance - _reserve0;
        uint256 token1Received = currentToken1Balance - _reserve1;

        uint256 _totalSupply = totalSupply;
        if(_totalSupply == 0){
            lpTokensToMint = Math.sqrt(token0Received * token1Received) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            lpTokensToMint = Math.min(token0Received * _totalSupply / _reserve0, token1Received * _totalSupply / _reserve1);
        }

        if(lpTokensToMint == 0) {
            revert NoLPTokensToMint();
        } 

        _mint(lpReceiver, lpTokensToMint);
        _update(currentToken0Balance, currentToken1Balance, _reserve0, _reserve1);

        emit Mint(lpReceiver, token0Received, token1Received);
    }

    // It is mandatory to send the amount of LP tokens that the user wants o burn before calling this function
    function burn(address to) external returns(uint256 token0ToTransfer, uint256 token1ToTransfer){
        address _token0 = token0;
        address _token1 = token1;
        uint256 _totalSupply = totalSupply;

        uint256 token0Amount = IERC20(_token0).balanceOf(address(this));
        uint256 token1Amount = IERC20(_token1).balanceOf(address(this));

        uint256 lpUserTokens = balanceOf[address(this)];

        token0ToTransfer = token0Amount * lpUserTokens / _totalSupply;
        token1ToTransfer = token1Amount * lpUserTokens / _totalSupply;

        if(token0ToTransfer==0 || token1ToTransfer==0){
            revert NoTokenToTransfer();
        }

        _burn(address(this), lpUserTokens);

        _safeTransfer(_token0, to, token0ToTransfer);
        _safeTransfer(_token1, to, token1ToTransfer);

        uint256 token0BalanceAfter = token0Amount - token0ToTransfer;
        uint256 token1BalanceAfter = token1Amount - token1ToTransfer;

        (uint112 _reserve0, uint112 _reserve1) = getReserves();

        _update(token0BalanceAfter, token1BalanceAfter, _reserve0, _reserve1);

        emit Burn(to, token0ToTransfer, token1ToTransfer);
    }

    function getReserves() public view returns(uint112 _reserve0, uint112 _reserve1){
        _reserve0 = reserve0;
        _reserve1 = reserve1;
    }

    // If someone sends tokens to the pair without calling mint or swap function, he can recover the amount by calling this function
    function skim(address to) external {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    // To match reserves and current balances use this function
    function sync() external {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

}