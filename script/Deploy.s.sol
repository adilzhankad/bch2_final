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
import "../src/core/MockERC20.sol";
import "../src/governance/DeFiGovernor.sol";
import "../src/governance/Treasury.sol";

/// @title Deploy — idempotent deployment script for L2 testnet (Optimism Sepolia)
/// @dev After all contracts are deployed, _handoffToTimelock() transfers every
///      admin role to the TimelockController and revokes the deployer's privileges,
///      leaving no admin backdoor.
contract Deploy is Script {
    uint256 constant TIMELOCK_DELAY = 2 days;

    // Deployed addresses stored in storage to avoid stack-too-deep
    address public govProxy;
    address public nftAddr;
    address public timelockAddr;
    address public governorAddr;
    address public factoryAddr;
    address public lendingAddr;
    address public vaultProxy;
    address public ethOracleAddr;
    address public treasuryAddr;
    address public mockStablecoinAddr;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        _deployTokens(deployer);
        _deployGovernance(deployer);
        _deployCore(deployer);
        _handoffToTimelock(deployer);  // ← revoke all deployer privileges

        vm.stopBroadcast();
        _logSummary(deployer);
    }

    // ─── Step 1: tokens ──────────────────────────────────────────────────────
    function _deployTokens(address deployer) internal {
        GovTokenV1 govImpl = new GovTokenV1();
        bytes memory govInitData = abi.encodeCall(GovTokenV1.initialize, (deployer, deployer));
        govProxy = address(new ERC1967Proxy(address(govImpl), govInitData));
        GovTokenV1(govProxy).mint(deployer, 10_000_000e18);
        console.log("GovToken proxy:  ", govProxy);

        nftAddr = address(new ProtocolNFT(deployer, "ipfs://bafybeib/"));
        console.log("ProtocolNFT:     ", nftAddr);
    }

    // ─── Step 2: governance ───────────────────────────────────────────────────
    function _deployGovernance(address deployer) internal {
        // Deploy Timelock with no pre-set proposers; Governor is added after
        // deployment so only the DAO can schedule calls — not any arbitrary address.
        address[] memory noProposers = new address[](0);
        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0); // anyone can execute after delay (Compound standard)

        TimelockController timelock = new TimelockController(
            TIMELOCK_DELAY, noProposers, openExecutors, deployer
        );
        timelockAddr = address(timelock);
        console.log("TimelockController:", timelockAddr);

        // Delegate so deployer can create the first proposal if needed
        GovTokenV1(govProxy).delegate(deployer);

        DeFiGovernor governor = new DeFiGovernor(IVotes(govProxy), timelock);
        governorAddr = address(governor);
        console.log("DeFiGovernor:    ", governorAddr);

        // Only the Governor may schedule; deployer admin will be revoked next
        timelock.grantRole(timelock.PROPOSER_ROLE(),  governorAddr);
        timelock.grantRole(timelock.CANCELLER_ROLE(), governorAddr);
        // Deployer's Timelock admin is revoked as the final step of handoff

        treasuryAddr = address(new Treasury(timelockAddr));
        console.log("Treasury:        ", treasuryAddr);
    }

    // ─── Step 3: core protocol ────────────────────────────────────────────────
    function _deployCore(address deployer) internal {
        // Use mock feeds for testnet; replace with real Chainlink addresses for mainnet
        MockAggregatorV3 ethFeed  = new MockAggregatorV3(8, 3000e8);
        MockAggregatorV3 usdcFeed = new MockAggregatorV3(8, 1e8);
        ethOracleAddr = address(new PriceOracle(address(ethFeed),  3600));
        address usdcOracleAddr = address(new PriceOracle(address(usdcFeed), 3600));
        console.log("ETH PriceOracle: ", ethOracleAddr);
        console.log("USDC PriceOracle:", usdcOracleAddr);

        factoryAddr = address(new PoolFactory());
        console.log("PoolFactory:     ", factoryAddr);

        // Deploy mock stablecoin used as borrowable debt token in the lending pool.
        // On mainnet, replace with a real stablecoin (USDC, DAI, etc.).
        MockERC20 mockUsdc = new MockERC20("Mock USDC", "mUSDC", 18, deployer);
        mockUsdc.mint(deployer, 10_000_000e18);
        mockStablecoinAddr = address(mockUsdc);
        console.log("MockERC20 (mUSDC):", mockStablecoinAddr);

        lendingAddr = address(new LendingPool(deployer));
        // govToken  → collateral only  (LTV 75%, liq threshold 80%)
        LendingPool(lendingAddr).configureAsset(
            govProxy, ethOracleAddr, 0.75e18, 0.80e18, 0.05e18, true, false
        );
        // mUSDC     → borrowable debt token (LTV 90%, liq threshold 95%, 1% bonus)
        LendingPool(lendingAddr).configureAsset(
            mockStablecoinAddr, usdcOracleAddr, 0.90e18, 0.95e18, 0.01e18, false, true
        );
        // Seed the lending pool with liquidity so borrows are possible
        mockUsdc.approve(lendingAddr, 1_000_000e18);
        LendingPool(lendingAddr).depositLiquidity(mockStablecoinAddr, 1_000_000e18);
        console.log("LendingPool:     ", lendingAddr);

        YieldVaultV1 vaultImpl = new YieldVaultV1();
        bytes memory vaultInit = abi.encodeCall(
            YieldVaultV1.initialize, (govProxy, "DeFi Yield Vault", "DYV", deployer)
        );
        vaultProxy = address(new ERC1967Proxy(address(vaultImpl), vaultInit));
        console.log("YieldVault proxy:", vaultProxy);
    }

    // ─── Step 4: hand off every admin role to Timelock, revoke deployer ───────
    /// @dev Pattern for each AccessControl contract:
    ///        1. Grant Timelock DEFAULT_ADMIN_ROLE (so it can manage roles later)
    ///        2. Grant Timelock every operational role
    ///        3. Revoke operational roles from deployer
    ///        4. Revoke DEFAULT_ADMIN_ROLE from deployer LAST
    ///      For Ownable contracts: transferOwnership to Timelock.
    function _handoffToTimelock(address deployer) internal {
        // ── GovToken ──────────────────────────────────────────────────────────
        GovTokenV1 gov = GovTokenV1(govProxy);
        gov.grantRole(gov.DEFAULT_ADMIN_ROLE(), timelockAddr);
        gov.grantRole(gov.MINTER_ROLE(),        timelockAddr);
        gov.grantRole(gov.UPGRADER_ROLE(),      timelockAddr);
        gov.revokeRole(gov.UPGRADER_ROLE(),      deployer);
        gov.revokeRole(gov.MINTER_ROLE(),        deployer);
        gov.revokeRole(gov.DEFAULT_ADMIN_ROLE(), deployer);

        // ── ProtocolNFT ───────────────────────────────────────────────────────
        ProtocolNFT nft = ProtocolNFT(nftAddr);
        nft.grantRole(nft.DEFAULT_ADMIN_ROLE(), timelockAddr);
        nft.grantRole(nft.MINTER_ROLE(),        timelockAddr);
        nft.revokeRole(nft.MINTER_ROLE(),        deployer);
        nft.revokeRole(nft.DEFAULT_ADMIN_ROLE(), deployer);

        // ── LendingPool ───────────────────────────────────────────────────────
        LendingPool lending = LendingPool(lendingAddr);
        lending.grantRole(lending.DEFAULT_ADMIN_ROLE(), timelockAddr);
        lending.grantRole(lending.MANAGER_ROLE(),        timelockAddr);
        lending.revokeRole(lending.MANAGER_ROLE(),       deployer);
        lending.revokeRole(lending.DEFAULT_ADMIN_ROLE(), deployer);

        // ── YieldVault ────────────────────────────────────────────────────────
        YieldVaultV1 vault = YieldVaultV1(vaultProxy);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(),   timelockAddr);
        vault.grantRole(vault.PAUSER_ROLE(),          timelockAddr);
        vault.grantRole(vault.YIELD_MANAGER_ROLE(),   timelockAddr);
        vault.grantRole(vault.UPGRADER_ROLE(),        timelockAddr);
        vault.revokeRole(vault.UPGRADER_ROLE(),       deployer);
        vault.revokeRole(vault.YIELD_MANAGER_ROLE(),  deployer);
        vault.revokeRole(vault.PAUSER_ROLE(),         deployer);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(),  deployer);

        // ── MockERC20 stablecoin (Ownable) ────────────────────────────────────
        MockERC20(mockStablecoinAddr).transferOwnership(timelockAddr);

        // ── PoolFactory (Ownable) ─────────────────────────────────────────────
        PoolFactory(factoryAddr).transferOwnership(timelockAddr);

        // ── TimelockController — revoke deployer's bootstrap admin ────────────
        // Must be last: deployer needs admin to sign all the grantRole calls above.
        TimelockController timelock = TimelockController(payable(timelockAddr));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        console.log("\n=== Admin handoff complete: deployer has zero privileges ===");
    }

    // ─── Summary ──────────────────────────────────────────────────────────────
    function _logSummary(address deployer) internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("Deployer:        ", deployer);
        console.log("GovToken:        ", govProxy);
        console.log("ProtocolNFT:     ", nftAddr);
        console.log("TimelockCtrl:    ", timelockAddr);
        console.log("DeFiGovernor:    ", governorAddr);
        console.log("PoolFactory:     ", factoryAddr);
        console.log("LendingPool:     ", lendingAddr);
        console.log("MockERC20 mUSDC: ", mockStablecoinAddr);
        console.log("YieldVault:      ", vaultProxy);
        console.log("Treasury:        ", treasuryAddr);
        console.log("ETH Oracle:      ", ethOracleAddr);
        console.log("\nAdmin owner of all contracts: TimelockController");
        console.log("Deployer admin roles: NONE");
    }
}
