// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./AMMPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title PoolFactory — deploys AMMPool instances via CREATE and CREATE2
contract PoolFactory is Ownable {
    mapping(address => mapping(address => address)) public getPool;
    address[] public allPools;

    event PoolCreated(address indexed token0, address indexed token1, address pool, uint256 poolIndex, bool viaCREATE2);

    error PoolExists();
    error IdenticalTokens();
    error ZeroAddress();
    error Create2Failed();

    constructor() Ownable(msg.sender) {}

    /// @notice Deploy a pool with CREATE (address not predictable)
    function createPool(address tokenA, address tokenB) external returns (address pool) {
        (address token0, address token1) = _sort(tokenA, tokenB);
        if (getPool[token0][token1] != address(0)) revert PoolExists();

        // CREATE — compiler picks the address
        pool = address(new AMMPool(token0, token1));
        _register(token0, token1, pool, false);
    }

    /// @notice Deploy a pool with CREATE2 (deterministic address)
    function createPool2(address tokenA, address tokenB, bytes32 salt) external returns (address pool) {
        (address token0, address token1) = _sort(tokenA, tokenB);
        if (getPool[token0][token1] != address(0)) revert PoolExists();

        bytes memory bytecode = abi.encodePacked(type(AMMPool).creationCode, abi.encode(token0, token1));
        assembly {
            pool := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        if (pool == address(0)) revert Create2Failed();
        _register(token0, token1, pool, true);
    }

    /// @notice Predict the CREATE2 address before deployment
    function predictPool(address tokenA, address tokenB, bytes32 salt) external view returns (address predicted) {
        (address token0, address token1) = _sort(tokenA, tokenB);
        bytes memory bytecode = abi.encodePacked(type(AMMPool).creationCode, abi.encode(token0, token1));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));
        predicted = address(uint160(uint256(hash)));
    }

    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    function _sort(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert IdenticalTokens();
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _register(address token0, address token1, address pool, bool viaCREATE2) internal {
        getPool[token0][token1] = pool;
        getPool[token1][token0] = pool;
        allPools.push(pool);
        emit PoolCreated(token0, token1, pool, allPools.length - 1, viaCREATE2);
    }
}
