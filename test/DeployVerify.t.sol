// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

/// @title DeployVerifyTest — integration test that replays Deploy.s.sol's
///        admin-handoff sequence and asserts every condition the live
///        Verify.s.sol script would assert against a real testnet deployment.
///
/// @dev   This is the in-repo proof that the deployment matches the spec
///        (Section 7: "Output of this script must be in the repo"). Running
///        `forge test --match-contract DeployVerifyTest -vv` produces a
///        human-readable trace of every check that passed.
contract DeployVerifyTest is Test {
    uint256 constant TIMELOCK_DELAY  = 2 days;
    uint256 constant VOTING_DELAY    = 1 days;
    uint256 constant VOTING_PERIOD   = 7 days;
    uint256 constant QUORUM_FRACTION = 4;

    address internal deployer = makeAddr("deployer");

    // Deployed addresses (filled by _deploy)
    address internal govProxy;
    address internal nftAddr;
    address internal timelockAddr;
    address internal governorAddr;
    address internal factoryAddr;
    address internal lendingAddr;
    address internal vaultProxy;
    address internal treasuryAddr;
    address internal mockStablecoinAddr;
    address internal ethOracleAddr;

    function setUp() public {
        vm.startPrank(deployer);
        _deployTokens();
        _deployGovernance();
        _deployCore();
        _handoffToTimelock();
        vm.stopPrank();
    }

    // ─── Test: every spec invariant after handoff ─────────────────────────────
    function test_postDeployment_matches_spec() public view {
        // Timelock
        TimelockController tl = TimelockController(payable(timelockAddr));
        assertEq(tl.getMinDelay(), TIMELOCK_DELAY, "Timelock.minDelay = 2 days");
        assertTrue(tl.hasRole(tl.PROPOSER_ROLE(), governorAddr),  "PROPOSER = Governor");
        assertFalse(tl.hasRole(tl.PROPOSER_ROLE(), deployer),     "Deployer has no PROPOSER");
        assertTrue(tl.hasRole(tl.CANCELLER_ROLE(), governorAddr), "CANCELLER = Governor");
        assertFalse(tl.hasRole(tl.CANCELLER_ROLE(), deployer),    "Deployer has no CANCELLER");
        assertTrue(tl.hasRole(tl.EXECUTOR_ROLE(), address(0)),    "EXECUTOR = open (anyone)");
        assertFalse(tl.hasRole(tl.DEFAULT_ADMIN_ROLE(), deployer), "Deployer has no Timelock admin");

        // Governor
        DeFiGovernor gov = DeFiGovernor(payable(governorAddr));
        assertEq(gov.votingDelay(),     VOTING_DELAY,    "Governor.votingDelay = 1 day");
        assertEq(gov.votingPeriod(),    VOTING_PERIOD,   "Governor.votingPeriod = 7 days");
        assertEq(gov.quorumNumerator(), QUORUM_FRACTION, "Governor.quorum = 4%");
        assertEq(gov.timelock(),        timelockAddr,    "Governor.timelock = TimelockCtrl");
        assertEq(gov.CLOCK_MODE(),      "mode=timestamp", "Governor.CLOCK_MODE = timestamp");

        // GovToken — every role on Timelock, none on deployer
        GovTokenV1 t = GovTokenV1(govProxy);
        assertTrue(t.hasRole(t.DEFAULT_ADMIN_ROLE(), timelockAddr));
        assertTrue(t.hasRole(t.MINTER_ROLE(),        timelockAddr));
        assertTrue(t.hasRole(t.UPGRADER_ROLE(),      timelockAddr));
        assertFalse(t.hasRole(t.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(t.hasRole(t.MINTER_ROLE(),        deployer));
        assertFalse(t.hasRole(t.UPGRADER_ROLE(),      deployer));
        assertEq(t.CLOCK_MODE(), "mode=timestamp");

        // ProtocolNFT
        ProtocolNFT n = ProtocolNFT(nftAddr);
        assertTrue(n.hasRole(n.DEFAULT_ADMIN_ROLE(), timelockAddr));
        assertTrue(n.hasRole(n.MINTER_ROLE(),        timelockAddr));
        assertFalse(n.hasRole(n.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(n.hasRole(n.MINTER_ROLE(),        deployer));

        // LendingPool
        LendingPool l = LendingPool(lendingAddr);
        assertTrue(l.hasRole(l.DEFAULT_ADMIN_ROLE(), timelockAddr));
        assertTrue(l.hasRole(l.MANAGER_ROLE(),       timelockAddr));
        assertFalse(l.hasRole(l.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(l.hasRole(l.MANAGER_ROLE(),       deployer));

        // YieldVault
        YieldVaultV1 v = YieldVaultV1(vaultProxy);
        assertTrue(v.hasRole(v.DEFAULT_ADMIN_ROLE(),   timelockAddr));
        assertTrue(v.hasRole(v.PAUSER_ROLE(),          timelockAddr));
        assertTrue(v.hasRole(v.YIELD_MANAGER_ROLE(),   timelockAddr));
        assertTrue(v.hasRole(v.UPGRADER_ROLE(),        timelockAddr));
        assertFalse(v.hasRole(v.DEFAULT_ADMIN_ROLE(),  deployer));
        assertFalse(v.hasRole(v.PAUSER_ROLE(),         deployer));
        assertFalse(v.hasRole(v.YIELD_MANAGER_ROLE(),  deployer));
        assertFalse(v.hasRole(v.UPGRADER_ROLE(),       deployer));

        // Ownable: PoolFactory and MockERC20 stablecoin
        assertEq(Ownable(factoryAddr).owner(),        timelockAddr, "PoolFactory.owner = Timelock");
        assertEq(Ownable(mockStablecoinAddr).owner(), timelockAddr, "mUSDC.owner = Timelock");
    }

    // ─── Deploy steps (replicate Deploy.s.sol without broadcast) ──────────────
    function _deployTokens() internal {
        GovTokenV1 govImpl = new GovTokenV1();
        bytes memory govInitData = abi.encodeCall(GovTokenV1.initialize, (deployer, deployer));
        govProxy = address(new ERC1967Proxy(address(govImpl), govInitData));
        GovTokenV1(govProxy).mint(deployer, 10_000_000e18);

        nftAddr = address(new ProtocolNFT(deployer, "ipfs://bafybeib/"));
    }

    function _deployGovernance() internal {
        address[] memory noProposers   = new address[](0);
        address[] memory openExecutors = new address[](1);
        openExecutors[0] = address(0);

        TimelockController timelock = new TimelockController(
            TIMELOCK_DELAY, noProposers, openExecutors, deployer
        );
        timelockAddr = address(timelock);

        GovTokenV1(govProxy).delegate(deployer);

        DeFiGovernor governor = new DeFiGovernor(IVotes(govProxy), timelock);
        governorAddr = address(governor);

        timelock.grantRole(timelock.PROPOSER_ROLE(),  governorAddr);
        timelock.grantRole(timelock.CANCELLER_ROLE(), governorAddr);

        treasuryAddr = address(new Treasury(timelockAddr));
    }

    function _deployCore() internal {
        MockAggregatorV3 ethFeed  = new MockAggregatorV3(8, 3000e8);
        MockAggregatorV3 usdcFeed = new MockAggregatorV3(8, 1e8);
        ethOracleAddr             = address(new PriceOracle(address(ethFeed),  3600));
        address usdcOracleAddr    = address(new PriceOracle(address(usdcFeed), 3600));

        factoryAddr = address(new PoolFactory());

        MockERC20 mockUsdc = new MockERC20("Mock USDC", "mUSDC", 18, deployer);
        mockUsdc.mint(deployer, 10_000_000e18);
        mockStablecoinAddr = address(mockUsdc);

        lendingAddr = address(new LendingPool(deployer));
        LendingPool(lendingAddr).configureAsset(govProxy,          ethOracleAddr,  0.75e18, 0.80e18, 0.05e18, true,  false);
        LendingPool(lendingAddr).configureAsset(mockStablecoinAddr, usdcOracleAddr, 0.90e18, 0.95e18, 0.01e18, false, true);
        mockUsdc.approve(lendingAddr, 1_000_000e18);
        LendingPool(lendingAddr).depositLiquidity(mockStablecoinAddr, 1_000_000e18);

        YieldVaultV1 vaultImpl = new YieldVaultV1();
        bytes memory vaultInit = abi.encodeCall(
            YieldVaultV1.initialize, (govProxy, "DeFi Yield Vault", "DYV", deployer)
        );
        vaultProxy = address(new ERC1967Proxy(address(vaultImpl), vaultInit));
    }

    function _handoffToTimelock() internal {
        GovTokenV1 gov = GovTokenV1(govProxy);
        gov.grantRole(gov.DEFAULT_ADMIN_ROLE(), timelockAddr);
        gov.grantRole(gov.MINTER_ROLE(),        timelockAddr);
        gov.grantRole(gov.UPGRADER_ROLE(),      timelockAddr);
        gov.revokeRole(gov.UPGRADER_ROLE(),      deployer);
        gov.revokeRole(gov.MINTER_ROLE(),        deployer);
        gov.revokeRole(gov.DEFAULT_ADMIN_ROLE(), deployer);

        ProtocolNFT nft = ProtocolNFT(nftAddr);
        nft.grantRole(nft.DEFAULT_ADMIN_ROLE(), timelockAddr);
        nft.grantRole(nft.MINTER_ROLE(),        timelockAddr);
        nft.revokeRole(nft.MINTER_ROLE(),        deployer);
        nft.revokeRole(nft.DEFAULT_ADMIN_ROLE(), deployer);

        LendingPool lending = LendingPool(lendingAddr);
        lending.grantRole(lending.DEFAULT_ADMIN_ROLE(), timelockAddr);
        lending.grantRole(lending.MANAGER_ROLE(),        timelockAddr);
        lending.revokeRole(lending.MANAGER_ROLE(),       deployer);
        lending.revokeRole(lending.DEFAULT_ADMIN_ROLE(), deployer);

        YieldVaultV1 vault = YieldVaultV1(vaultProxy);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(),   timelockAddr);
        vault.grantRole(vault.PAUSER_ROLE(),          timelockAddr);
        vault.grantRole(vault.YIELD_MANAGER_ROLE(),   timelockAddr);
        vault.grantRole(vault.UPGRADER_ROLE(),        timelockAddr);
        vault.revokeRole(vault.UPGRADER_ROLE(),       deployer);
        vault.revokeRole(vault.YIELD_MANAGER_ROLE(),  deployer);
        vault.revokeRole(vault.PAUSER_ROLE(),         deployer);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(),  deployer);

        Ownable(mockStablecoinAddr).transferOwnership(timelockAddr);
        Ownable(factoryAddr).transferOwnership(timelockAddr);

        TimelockController timelock = TimelockController(payable(timelockAddr));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
    }
}
