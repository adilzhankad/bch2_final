// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

contract SqrtImplementations {
    function sqrtYul(uint256 x) public pure returns (uint256 y) {
        assembly {
            switch x
            case 0 { y := 0 }
            default {
                y := x
                let z := add(div(x, 2), 1)
                for {} lt(z, y) {} {
                    y := z
                    z := div(add(div(x, z), z), 2)
                }
            }
        }
    }

    function sqrtSolidity(uint256 x) public pure returns (uint256 y) {
        if (x == 0) return 0;
        y = x;
        uint256 z = x / 2 + 1;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

contract YulBenchmarkTest is Test {
    SqrtImplementations internal impl;

    uint256[4] internal LARGE_INPUTS = [
        uint256(1_000e18 * 1_000e18),
        uint256(10_000e18 * 10_000e18),
        uint256(100_000e18 * 100_000e18),
        uint256(type(uint128).max)
    ];

    function setUp() public {
        impl = new SqrtImplementations();
    }

    function test_yul_matches_solidity_zero() public view {
        assertEq(impl.sqrtYul(0), impl.sqrtSolidity(0));
    }

    function test_yul_matches_solidity_small() public view {
        for (uint256 i = 1; i <= 100; i++) {
            assertEq(impl.sqrtYul(i), impl.sqrtSolidity(i));
        }
    }

    function test_yul_matches_solidity_large() public view {
        assertEq(impl.sqrtYul(1_000_000e18), impl.sqrtSolidity(1_000_000e18));
        assertEq(
            impl.sqrtYul(100_000e18 * 100_000e18),
            impl.sqrtSolidity(100_000e18 * 100_000e18)
        );
        assertEq(impl.sqrtYul(type(uint256).max / 4), impl.sqrtSolidity(type(uint256).max / 4));
    }

    function testFuzz_yul_matches_solidity(uint256 x) public view {
        x = bound(x, 0, type(uint256).max / 4);
        assertEq(impl.sqrtYul(x), impl.sqrtSolidity(x));
    }

    function test_benchmark_sqrt_large_inputs() public {
        uint256 totalYulGas;
        uint256 totalSolGas;

        for (uint256 i = 0; i < LARGE_INPUTS.length; i++) {
            uint256 input = LARGE_INPUTS[i];

            uint256 g0 = gasleft();
            impl.sqrtYul(input);
            uint256 yulGas = g0 - gasleft();

            uint256 g1 = gasleft();
            impl.sqrtSolidity(input);
            uint256 solGas = g1 - gasleft();

            totalYulGas += yulGas;
            totalSolGas += solGas;

            emit log_named_uint("Input index  ", i);
            emit log_named_uint("  Yul gas    ", yulGas);
            emit log_named_uint("  Solidity   ", solGas);
            emit log_named_uint("  Saved gas  ", solGas - yulGas);
            emit log_named_uint("  Savings %  ", ((solGas - yulGas) * 100) / solGas);

            assertLt(yulGas, solGas, "Yul must be cheaper than Solidity for large inputs");
        }

        emit log_named_uint("TOTAL Yul     ", totalYulGas);
        emit log_named_uint("TOTAL Solidity", totalSolGas);
        emit log_named_uint("TOTAL Saved   ", totalSolGas - totalYulGas);
        emit log_named_uint("TOTAL Savings%", ((totalSolGas - totalYulGas) * 100) / totalSolGas);
        assertLt(totalYulGas, totalSolGas, "Yul total gas must be less than Solidity total");
    }

    function test_benchmark_amm_initial_mint_scenario() public {
        uint256 amount0 = 100_000e18;
        uint256 amount1 = 100_000e18;
        uint256 product = amount0 * amount1;

        uint256 g0 = gasleft();
        uint256 yulResult = impl.sqrtYul(product);
        uint256 yulGas = g0 - gasleft();

        uint256 g1 = gasleft();
        uint256 solResult = impl.sqrtSolidity(product);
        uint256 solGas = g1 - gasleft();

        assertEq(yulResult, solResult, "Both implementations must return same result");
        assertLt(yulGas, solGas, "Yul must be cheaper for AMM initial mint");

        emit log_string("=== AMMPool.addLiquidity sqrt(100_000e18 * 100_000e18) ===");
        emit log_named_uint("Yul gas  ", yulGas);
        emit log_named_uint("Pure gas ", solGas);
        emit log_named_uint("Saved    ", solGas - yulGas);
        emit log_named_uint("Savings %", ((solGas - yulGas) * 100) / solGas);
    }
}
