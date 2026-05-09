// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/tokens/GovToken.sol";

contract GovTokenTest is Test {
    GovTokenV1 internal impl;
    GovTokenV1 internal token;
    address internal admin = makeAddr("admin");
    address internal minter = makeAddr("minter");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    bytes32 internal MINTER_ROLE;
    bytes32 internal UPGRADER_ROLE;

    function setUp() public {
        impl = new GovTokenV1();
        bytes memory initData = abi.encodeCall(GovTokenV1.initialize, (admin, minter));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        token = GovTokenV1(address(proxy));
        MINTER_ROLE = token.MINTER_ROLE();
        UPGRADER_ROLE = token.UPGRADER_ROLE();
    }

    // ── Basic ERC20 ────────────────────────────────────────────────────────────
    function test_name() public view {
        assertEq(token.name(), "DeFi Gov Token");
    }

    function test_symbol() public view {
        assertEq(token.symbol(), "DGT");
    }

    function test_decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_mint_byMinter() public {
        vm.prank(minter);
        token.mint(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
    }

    function test_mint_revert_notMinter() public {
        vm.expectRevert();
        vm.prank(alice);
        token.mint(alice, 1);
    }

    function test_mint_revert_capExceeded() public {
        uint256 cap = token.MAX_SUPPLY();
        vm.prank(minter);
        token.mint(alice, cap);
        vm.prank(minter);
        vm.expectRevert("GovToken: cap exceeded");
        token.mint(alice, 1);
    }

    function test_burn() public {
        vm.prank(minter);
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.burn(400e18);
        assertEq(token.balanceOf(alice), 600e18);
    }

    // ── Votes ─────────────────────────────────────────────────────────────────
    function test_delegate_and_votes() public {
        vm.prank(minter);
        token.mint(alice, 1000e18);
        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), 1000e18);
    }

    function test_delegate_to_bob() public {
        vm.prank(minter);
        token.mint(alice, 500e18);
        vm.prank(alice);
        token.delegate(bob);
        assertEq(token.getVotes(bob), 500e18);
        assertEq(token.getVotes(alice), 0);
    }

    function test_pastVotes() public {
        vm.prank(minter);
        token.mint(alice, 200e18);
        vm.prank(alice);
        token.delegate(alice);
        uint256 snapshot = block.number;
        vm.roll(block.number + 1);
        assertEq(token.getPastVotes(alice, snapshot), 200e18);
    }

    // ── Permit ────────────────────────────────────────────────────────────────
    function test_permit() public {
        uint256 alicePk = 0xA11CE;
        address aliceAddr = vm.addr(alicePk);
        vm.prank(minter);
        token.mint(aliceAddr, 100e18);

        uint256 nonce = token.nonces(aliceAddr);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(
                    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                    aliceAddr, bob, 50e18, nonce, deadline
                ))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);
        token.permit(aliceAddr, bob, 50e18, deadline, v, r, s);
        assertEq(token.allowance(aliceAddr, bob), 50e18);
    }

    // ── UUPS upgrade ──────────────────────────────────────────────────────────
    function test_upgradeToV2() public {
        GovTokenV2 implV2 = new GovTokenV2();
        vm.prank(admin);
        token.upgradeToAndCall(address(implV2), "");
        GovTokenV2 v2 = GovTokenV2(address(token));
        assertEq(v2.version(), "2.0.0");
        assertEq(v2.VERSION(), 2);
    }

    function test_upgrade_revert_notUpgrader() public {
        GovTokenV2 implV2 = new GovTokenV2();
        vm.expectRevert();
        vm.prank(alice);
        token.upgradeToAndCall(address(implV2), "");
    }

    // ── Access control ────────────────────────────────────────────────────────
    function test_grantMinterRole() public {
        // Cache role bytes BEFORE prank to avoid consuming prank on role getter
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, alice);
        vm.prank(alice);
        token.mint(bob, 1e18);
        assertEq(token.balanceOf(bob), 1e18);
    }

    function test_clock() public view {
        assertEq(token.clock(), uint48(block.number));
    }

    // ── Fuzz: delegated voting power always equals delegator's balance ────────
    function testFuzz_votingPower_equals_balance_after_delegation(uint256 mintAmount) public {
        mintAmount = bound(mintAmount, 1, token.MAX_SUPPLY() - token.totalSupply());

        vm.prank(minter);
        token.mint(alice, mintAmount);

        // Self-delegate so votes are activated
        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), mintAmount, "Votes must equal balance after self-delegation");

        // Delegate to bob — all votes move to bob, alice drops to zero
        vm.prank(alice);
        token.delegate(bob);

        assertEq(token.getVotes(bob),   mintAmount, "Bob must receive all delegated votes");
        assertEq(token.getVotes(alice), 0,          "Alice must have zero votes after delegation");
    }
}
