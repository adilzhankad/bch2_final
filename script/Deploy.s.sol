// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../src/tokens/GovToken.sol";
import "../src/tokens/ProtocolNFT.sol";
import "../src/core/AMMPool.sol";
import "../src/core/PoolFactory.sol";
import "../src/core/LendingPool.sol";
import "../src/core/YieldVault.sol";
import "../src/core/PriceOracle.sol";
import "../src/core/MockAggregatorV3.sol";
import "../src/governance/DeFiGovernor.sol";
import "../src/governance/Treasury.sol";

/// @title Deploy — idempotent deployment script for L2 testnet (Optimism Sepolia)
contract Deploy is Script {
    uint256 constant TIMELOCK_DELAY = 2 days;

    // Deployed addresses stored in storage to avoid stack pressure
    address public govProxy;
    address public nftAddr;
    address public timelockAddr;
    address public governorAddr;
    address public factoryAddr;
    address public lendingAddr;
    address public vaultProxy;
    address public ethOracleAddr;
    address public treasuryAddr;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        _deployTokens(deployer);
        _deployGovernance(deployer);
        _deployCore(deployer);
        vm.stopBroadcast();
        _logSummary(deployer);
    }

    function _deployTokens(address deployer) internal {
        GovTokenV1 govImpl = new GovTokenV1();
        bytes memory govInitData = abi.encodeCall(GovTokenV1.initialize, (deployer, deployer));
        govProxy = address(new ERC1967Proxy(address(govImpl), govInitData));
        GovTokenV1(govProxy).mint(deployer, 10_000_000e18);
        console.log("GovToken proxy:", govProxy);

        nftAddr = address(new ProtocolNFT(deployer, "ipfs://bafybeib/"));
        console.log("ProtocolNFT:", nftAddr);
    }

    function _deployGovernance(address deployer) internal {
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0);
        executors[0] = address(0);
        TimelockController timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);
        timelockAddr = address(timelock);
        console.log("TimelockController:", timelockAddr);

        GovTokenV1(govProxy).delegate(deployer);
        DeFiGovernor governor = new DeFiGovernor(IVotes(govProxy), timelock);
        governorAddr = address(governor);
        console.log("DeFiGovernor:", governorAddr);

        timelock.grantRole(timelock.PROPOSER_ROLE(), governorAddr);
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        treasuryAddr = address(new Treasury(timelockAddr));
        console.log("Treasury:", treasuryAddr);
    }

    function _deployCore(address deployer) internal {
        MockAggregatorV3 ethFeed = new MockAggregatorV3(8, 3000e8);
        MockAggregatorV3 usdcFeed = new MockAggregatorV3(8, 1e8);
        ethOracleAddr = address(new PriceOracle(address(ethFeed), 3600));
        address usdcOracleAddr = address(new PriceOracle(address(usdcFeed), 3600));
        console.log("ETH PriceOracle:", ethOracleAddr);
        console.log("USDC PriceOracle:", usdcOracleAddr);

        factoryAddr = address(new PoolFactory());
        console.log("PoolFactory:", factoryAddr);

        lendingAddr = address(new LendingPool(deployer));
        LendingPool(lendingAddr).configureAsset(
            govProxy, ethOracleAddr, 0.75e18, 0.80e18, 0.05e18, true, false
        );
        console.log("LendingPool:", lendingAddr);

        YieldVaultV1 vaultImpl = new YieldVaultV1();
        bytes memory vaultInit = abi.encodeCall(
            YieldVaultV1.initialize, (govProxy, "DeFi Yield Vault", "DYV", deployer)
        );
        vaultProxy = address(new ERC1967Proxy(address(vaultImpl), vaultInit));
        console.log("YieldVault proxy:", vaultProxy);
        console.log("Treasury:        ", treasuryAddr);
    }

    function _logSummary(address deployer) internal view {
        console.log("\n=== Deployment Complete ===");
        console.log("Deployer:     ", deployer);
        console.log("GovToken:     ", govProxy);
        console.log("ProtocolNFT:  ", nftAddr);
        console.log("TimelockCtrl: ", timelockAddr);
        console.log("DeFiGovernor: ", governorAddr);
        console.log("PoolFactory:  ", factoryAddr);
        console.log("LendingPool:  ", lendingAddr);
        console.log("YieldVault:   ", vaultProxy);
    }
}
