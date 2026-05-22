// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "../src/tokens/GovToken.sol";
import "../src/tokens/ProtocolNFT.sol";
import "../src/governance/DeFiGovernor.sol";
import "../src/governance/Treasury.sol";

contract GovernanceTest is Test {
    GovTokenV1 internal token;
    TimelockController internal timelock;
    DeFiGovernor internal governor;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    bytes32 internal MINTER_ROLE;
    bytes32 internal PROPOSER_ROLE;
    bytes32 internal EXECUTOR_ROLE;
    bytes32 internal CANCELLER_ROLE;
    bytes32 internal ADMIN_ROLE;

    uint256 constant INITIAL_SUPPLY = 10_000_000e18;
    uint256 constant TWO_DAYS = 2 days;

    function setUp() public {
        // Deploy GovToken
        GovTokenV1 impl = new GovTokenV1();
        bytes memory initData = abi.encodeCall(GovTokenV1.initialize, (admin, admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = GovTokenV1(address(proxy));
        MINTER_ROLE = token.MINTER_ROLE();

        // Mint and distribute
        vm.startPrank(admin);
        token.mint(alice, 5_000_000e18);
        token.mint(bob, 3_000_000e18);
        token.mint(carol, 2_000_000e18);
        vm.stopPrank();

        // Delegate votes
        vm.prank(alice);  token.delegate(alice);
        vm.prank(bob);    token.delegate(bob);
        vm.prank(carol);  token.delegate(carol);

        // Deploy TimelockController with 2-day delay
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0);
        executors[0] = address(0);
        timelock = new TimelockController(TWO_DAYS, proposers, executors, admin);

        // Cache timelock role bytes before any pranks
        PROPOSER_ROLE  = timelock.PROPOSER_ROLE();
        EXECUTOR_ROLE  = timelock.EXECUTOR_ROLE();
        CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        ADMIN_ROLE     = timelock.DEFAULT_ADMIN_ROLE();

        // Deploy Governor
        governor = new DeFiGovernor(IVotes(address(token)), timelock);

        // Wire up timelock roles (use startPrank so multiple calls are covered)
        vm.startPrank(admin);
        timelock.grantRole(PROPOSER_ROLE, address(governor));
        timelock.grantRole(CANCELLER_ROLE, address(governor));
        vm.stopPrank();

        // Advance one second so getPastTotalSupply(clock-1) works (timestamp clock)
        vm.warp(block.timestamp + 1);
    }

    // ── Governor parameters ────────────────────────────────────────────────────
    function test_votingDelay() public view {
        assertEq(governor.votingDelay(), 1 days);
    }

    function test_votingPeriod() public view {
        assertEq(governor.votingPeriod(), 7 days);
    }

    function test_quorumFraction() public view {
        assertEq(governor.quorumNumerator(), 4);
    }

    function test_proposalThreshold_1pct() public view {
        uint256 threshold = governor.proposalThreshold();
        assertEq(threshold, INITIAL_SUPPLY / 100);
    }

    function test_timelockDelay() public view {
        assertEq(timelock.getMinDelay(), TWO_DAYS);
    }

    // ── Full governance lifecycle ──────────────────────────────────────────────
    function test_fullGovernanceCycle() public {
        // 1. Prepare proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(GovTokenV1.mint, (carol, 1e18));
        string memory description = "Proposal #1: Mint 1 DGT to carol";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // 2. Advance past voting delay
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // 3. Vote
        vm.prank(alice); governor.castVote(proposalId, 1); // For
        vm.prank(bob);   governor.castVote(proposalId, 1); // For
        vm.prank(carol); governor.castVote(proposalId, 0); // Against

        // 4. End voting period
        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // 5. Queue in timelock
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // 6. Wait for timelock delay
        vm.warp(block.timestamp + TWO_DAYS + 1);

        // Grant minting permission to timelock (admin still has it in setUp)
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, address(timelock));

        // 7. Execute
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
        assertEq(token.balanceOf(carol), 2_000_000e18 + 1e18);
    }

    // ── Vote with reason ────────────────────────────────────────────────────────
    function test_castVoteWithReason() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);
        calldatas[0] = "";
        string memory description = "Test vote with reason";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVoteWithReason(proposalId, 1, "I support this");
        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertGt(forVotes, 0);
    }

    // ── Defeated proposal ──────────────────────────────────────────────────────
    function test_proposalDefeated() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);
        string memory description = "Proposal to defeat";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(alice); governor.castVote(proposalId, 0);
        vm.prank(bob);   governor.castVote(proposalId, 0);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ── NFT mint ───────────────────────────────────────────────────────────────
    function test_nft_mint_byMinter() public {
        address nftAdmin = makeAddr("nftAdmin");
        ProtocolNFT nft = new ProtocolNFT(nftAdmin, "ipfs://base/");

        vm.prank(nftAdmin);
        uint256 tokenId = nft.safeMint(alice, "ipfs://base/1.json");

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(nft.totalSupply(), 1);
        assertEq(tokenId, 0);
    }

    function test_nft_mint_revert_notMinter() public {
        address nftAdmin = makeAddr("nftAdmin");
        ProtocolNFT nft = new ProtocolNFT(nftAdmin, "ipfs://base/");

        vm.expectRevert();
        vm.prank(alice);
        nft.safeMint(alice, "ipfs://base/1.json");
    }

    // ── Governance fuzz tests ──────────────────────────────────────────────────
    function test_timelock_controls_treasury() public {
        Treasury treasury = new Treasury(address(timelock));

        vm.deal(address(treasury), 1 ether);
        assertEq(address(treasury).balance, 1 ether);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(Treasury.releaseETH, (payable(carol), 0.5 ether));
        string memory description = "Proposal: release 0.5 ETH to carol";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + governor.votingDelay() + 1);
        vm.prank(alice); governor.castVote(proposalId, 1);
        vm.prank(bob);   governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);

        vm.warp(block.timestamp + TWO_DAYS + 1);
        governor.execute(targets, values, calldatas, descHash);

        assertEq(carol.balance, 0.5 ether);
    }

    function testFuzz_votingPower_equalsDelegatedBalance(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);

        address voter = makeAddr("voter");
        vm.prank(admin);
        token.mint(voter, amount);

        vm.prank(voter);
        token.delegate(voter);

        // Advance one second so getPastVotes works (timestamp clock)
        vm.warp(block.timestamp + 1);

        assertEq(token.getVotes(voter), amount);
        assertEq(token.getPastVotes(voter, block.timestamp - 1), amount);
    }

    function testFuzz_quorum_scalesWithTotalSupply(uint256 extraMint) public {
        extraMint = bound(extraMint, 1e18, 1_000_000e18);

        uint256 supplyBefore = token.totalSupply();
        uint256 quorumBefore = governor.quorum(block.timestamp - 1);

        vm.prank(admin);
        token.mint(makeAddr("extra"), extraMint);
        vm.warp(block.timestamp + 1);

        uint256 quorumAfter = governor.quorum(block.timestamp - 1);

        assertGt(token.totalSupply(), supplyBefore);
        assertGt(quorumAfter, quorumBefore, "Quorum must increase as supply grows");
    }

    // ── proposalNeedsQueuing always true for timelock-controlled governor ──────
    function test_proposalNeedsQueuing() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);
        calldatas[0] = "";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "needsQueuing test");
        assertTrue(governor.proposalNeedsQueuing(proposalId));
    }

    // ── hasVoted toggles after castVote ────────────────────────────────────────
    function test_hasVoted_afterCast() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);
        calldatas[0] = "";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "hasVoted test");
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        assertFalse(governor.hasVoted(proposalId, alice));
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        assertTrue(governor.hasVoted(proposalId, alice));
    }

    // ── Cancellation by proposer while proposal still Pending ──────────────────
    function test_cancel_byProposer() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(0);
        calldatas[0] = "";
        string memory description = "cancel test";

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        bytes32 descHash = keccak256(bytes(description));
        vm.prank(alice);
        governor.cancel(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Canceled));
    }

    // ── name + CLOCK_MODE getters ─────────────────────────────────────────────
    function test_name_and_clockMode() public view {
        assertEq(governor.name(), "DeFiGovernor");
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
    }
}
