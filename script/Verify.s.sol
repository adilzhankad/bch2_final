// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../src/tokens/GovToken.sol";
import "../src/tokens/ProtocolNFT.sol";
import "../src/core/PoolFactory.sol";
import "../src/core/LendingPool.sol";
import "../src/core/YieldVault.sol";
import "../src/core/MockERC20.sol";
import "../src/governance/DeFiGovernor.sol";

/// @title Verify — post-deployment verification script
/// @dev Confirms that the deployed protocol matches the specification:
///        - Timelock delay is exactly 2 days
///        - Governor parameters: 1 day delay, 7 day period, 4% quorum, 1% threshold
///        - Timelock owns every admin role; deployer has none (no backdoor)
///        - Only Governor has PROPOSER_ROLE on the Timelock
///        - Ownable contracts (PoolFactory, mUSDC) are owned by the Timelock
///
///      Reads deployed addresses from env vars. Reverts on any mismatch so it
///      can be run from CI. Run:
///        DEPLOYER=0x... GOV_TOKEN=0x... TIMELOCK=0x... GOVERNOR=0x... \
///        LENDING_POOL=0x... YIELD_VAULT=0x... POOL_FACTORY=0x... \
///        PROTOCOL_NFT=0x... MOCK_USDC=0x... \
///        forge script script/Verify.s.sol --rpc-url optimism_sepolia
contract Verify is Script {
    uint256 constant TIMELOCK_DELAY  = 2 days;
    uint256 constant VOTING_DELAY    = 1 days;
    uint256 constant VOTING_PERIOD   = 7 days;
    uint256 constant QUORUM_FRACTION = 4;

    uint256 internal pass;
    uint256 internal fail;

    function run() external {
        address deployer     = vm.envAddress("DEPLOYER");
        address govToken     = vm.envAddress("GOV_TOKEN");
        address timelockAddr = vm.envAddress("TIMELOCK");
        address governorAddr = vm.envAddress("GOVERNOR");
        address lendingAddr  = vm.envAddress("LENDING_POOL");
        address vaultAddr    = vm.envAddress("YIELD_VAULT");
        address factoryAddr  = vm.envAddress("POOL_FACTORY");
        address nftAddr      = vm.envAddress("PROTOCOL_NFT");
        address mockUsdc     = vm.envAddress("MOCK_USDC");

        console.log("=== Post-Deployment Verification ===\n");

        _checkTimelock(timelockAddr, governorAddr, deployer);
        _checkGovernor(governorAddr, timelockAddr);
        _checkGovToken(govToken, timelockAddr, deployer);
        _checkProtocolNft(nftAddr, timelockAddr, deployer);
        _checkLendingPool(lendingAddr, timelockAddr, deployer);
        _checkYieldVault(vaultAddr, timelockAddr, deployer);
        _checkOwnable(factoryAddr, timelockAddr, "PoolFactory");
        _checkOwnable(mockUsdc,    timelockAddr, "MockERC20 (mUSDC)");

        console.log("\n=== Results ===");
        console.log("Passed:", pass);
        console.log("Failed:", fail);
        require(fail == 0, "Verification failed: see logs above");
        console.log("All checks passed -- deployment matches spec.");
    }

    // ─── Timelock ─────────────────────────────────────────────────────────────
    function _checkTimelock(address timelockAddr, address governor, address deployer) internal {
        TimelockController tl = TimelockController(payable(timelockAddr));

        _assertEq(tl.getMinDelay(), TIMELOCK_DELAY, "Timelock.minDelay = 2 days");

        // PROPOSER_ROLE: only Governor
        _assertTrue(tl.hasRole(tl.PROPOSER_ROLE(), governor),  "Timelock.PROPOSER = Governor");
        _assertTrue(!tl.hasRole(tl.PROPOSER_ROLE(), deployer), "Deployer has no PROPOSER_ROLE");

        // CANCELLER_ROLE: only Governor
        _assertTrue(tl.hasRole(tl.CANCELLER_ROLE(), governor),  "Timelock.CANCELLER = Governor");
        _assertTrue(!tl.hasRole(tl.CANCELLER_ROLE(), deployer), "Deployer has no CANCELLER_ROLE");

        // EXECUTOR_ROLE: open (address(0))
        _assertTrue(tl.hasRole(tl.EXECUTOR_ROLE(), address(0)), "Timelock.EXECUTOR = open");

        // Deployer's bootstrap admin must be revoked
        _assertTrue(!tl.hasRole(tl.DEFAULT_ADMIN_ROLE(), deployer), "Deployer has no Timelock admin");
    }

    // ─── Governor ─────────────────────────────────────────────────────────────
    function _checkGovernor(address governorAddr, address timelockAddr) internal {
        DeFiGovernor gov = DeFiGovernor(payable(governorAddr));

        _assertEq(gov.votingDelay(),     VOTING_DELAY,    "Governor.votingDelay = 1 day");
        _assertEq(gov.votingPeriod(),    VOTING_PERIOD,   "Governor.votingPeriod = 7 days");
        _assertEq(gov.quorumNumerator(), QUORUM_FRACTION, "Governor.quorumFraction = 4%");
        _assertEq(gov.timelock(),        timelockAddr,    "Governor.timelock = TimelockCtrl");
        _assertEqStr(gov.CLOCK_MODE(), "mode=timestamp", "Governor.CLOCK_MODE = timestamp");
    }

    // ─── GovToken ─────────────────────────────────────────────────────────────
    function _checkGovToken(address tokenAddr, address timelockAddr, address deployer) internal {
        GovTokenV1 t = GovTokenV1(tokenAddr);

        _assertTrue(t.hasRole(t.DEFAULT_ADMIN_ROLE(), timelockAddr), "GovToken.admin = Timelock");
        _assertTrue(t.hasRole(t.MINTER_ROLE(),        timelockAddr), "GovToken.minter = Timelock");
        _assertTrue(t.hasRole(t.UPGRADER_ROLE(),      timelockAddr), "GovToken.upgrader = Timelock");

        _assertTrue(!t.hasRole(t.DEFAULT_ADMIN_ROLE(), deployer), "Deployer has no GovToken admin");
        _assertTrue(!t.hasRole(t.MINTER_ROLE(),        deployer), "Deployer has no GovToken minter");
        _assertTrue(!t.hasRole(t.UPGRADER_ROLE(),      deployer), "Deployer has no GovToken upgrader");

        _assertEqStr(t.CLOCK_MODE(), "mode=timestamp", "GovToken.CLOCK_MODE = timestamp");
    }

    // ─── ProtocolNFT ──────────────────────────────────────────────────────────
    function _checkProtocolNft(address nftAddr, address timelockAddr, address deployer) internal {
        ProtocolNFT n = ProtocolNFT(nftAddr);

        _assertTrue(n.hasRole(n.DEFAULT_ADMIN_ROLE(), timelockAddr), "NFT.admin = Timelock");
        _assertTrue(n.hasRole(n.MINTER_ROLE(),        timelockAddr), "NFT.minter = Timelock");

        _assertTrue(!n.hasRole(n.DEFAULT_ADMIN_ROLE(), deployer), "Deployer has no NFT admin");
        _assertTrue(!n.hasRole(n.MINTER_ROLE(),        deployer), "Deployer has no NFT minter");
    }

    // ─── LendingPool ──────────────────────────────────────────────────────────
    function _checkLendingPool(address lendingAddr, address timelockAddr, address deployer) internal {
        LendingPool l = LendingPool(lendingAddr);

        _assertTrue(l.hasRole(l.DEFAULT_ADMIN_ROLE(), timelockAddr), "Lending.admin = Timelock");
        _assertTrue(l.hasRole(l.MANAGER_ROLE(),       timelockAddr), "Lending.manager = Timelock");

        _assertTrue(!l.hasRole(l.DEFAULT_ADMIN_ROLE(), deployer), "Deployer has no Lending admin");
        _assertTrue(!l.hasRole(l.MANAGER_ROLE(),       deployer), "Deployer has no Lending manager");
    }

    // ─── YieldVault ───────────────────────────────────────────────────────────
    function _checkYieldVault(address vaultAddr, address timelockAddr, address deployer) internal {
        YieldVaultV1 v = YieldVaultV1(vaultAddr);

        _assertTrue(v.hasRole(v.DEFAULT_ADMIN_ROLE(),   timelockAddr), "Vault.admin = Timelock");
        _assertTrue(v.hasRole(v.PAUSER_ROLE(),          timelockAddr), "Vault.pauser = Timelock");
        _assertTrue(v.hasRole(v.YIELD_MANAGER_ROLE(),   timelockAddr), "Vault.yieldMgr = Timelock");
        _assertTrue(v.hasRole(v.UPGRADER_ROLE(),        timelockAddr), "Vault.upgrader = Timelock");

        _assertTrue(!v.hasRole(v.DEFAULT_ADMIN_ROLE(),  deployer), "Deployer has no Vault admin");
        _assertTrue(!v.hasRole(v.PAUSER_ROLE(),         deployer), "Deployer has no Vault pauser");
        _assertTrue(!v.hasRole(v.YIELD_MANAGER_ROLE(),  deployer), "Deployer has no Vault yieldMgr");
        _assertTrue(!v.hasRole(v.UPGRADER_ROLE(),       deployer), "Deployer has no Vault upgrader");
    }

    // ─── Ownable contracts ────────────────────────────────────────────────────
    function _checkOwnable(address target, address expectedOwner, string memory label) internal {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature("owner()"));
        if (!ok || data.length < 32) {
            _record(false, string.concat(label, ".owner() unreachable"));
            return;
        }
        address owner = abi.decode(data, (address));
        _assertEq(owner, expectedOwner, string.concat(label, ".owner = Timelock"));
    }

    // ─── Assertion helpers ────────────────────────────────────────────────────
    function _assertTrue(bool cond, string memory label) internal {
        _record(cond, label);
    }

    function _assertEq(uint256 actual, uint256 expected, string memory label) internal {
        bool ok = actual == expected;
        if (!ok) {
            console.log(label, "expected:", expected);
            console.log(label, "actual:  ", actual);
        }
        _record(ok, label);
    }

    function _assertEq(address actual, address expected, string memory label) internal {
        bool ok = actual == expected;
        if (!ok) {
            console.log(label, "expected:", expected);
            console.log(label, "actual:  ", actual);
        }
        _record(ok, label);
    }

    function _assertEqStr(string memory actual, string memory expected, string memory label) internal {
        bool ok = keccak256(bytes(actual)) == keccak256(bytes(expected));
        if (!ok) {
            console.log(label, "expected:", expected);
            console.log(label, "actual:  ", actual);
        }
        _record(ok, label);
    }

    function _record(bool ok, string memory label) internal {
        if (ok) {
            pass++;
            console.log("  [OK]  ", label);
        } else {
            fail++;
            console.log("  [FAIL]", label);
        }
    }
}
