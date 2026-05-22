// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/governance/Treasury.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

/// @dev Contract that rejects incoming ETH, used to exercise the failure branch
///      of Treasury.releaseETH.
contract EthRejector {
    receive() external payable {
        revert("rejected");
    }
}

contract TreasuryTest is Test {
    Treasury internal treasury;
    MockERC20 internal token;

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        treasury = new Treasury(admin);
        token = new MockERC20();
    }

    // ── Constructor wires both roles to the timelock/admin ────────────────────
    function test_constructor_grantsRoles() public view {
        assertTrue(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(treasury.hasRole(treasury.SPENDER_ROLE(), admin));
    }

    // ── ERC-20 release ────────────────────────────────────────────────────────
    function test_releaseERC20() public {
        token.mint(address(treasury), 1000e18);

        vm.expectEmit(true, true, false, true, address(treasury));
        emit Treasury.ERC20Released(address(token), bob, 250e18);

        vm.prank(admin);
        treasury.releaseERC20(address(token), bob, 250e18);

        assertEq(token.balanceOf(bob), 250e18);
        assertEq(token.balanceOf(address(treasury)), 750e18);
    }

    function test_releaseERC20_revert_notSpender() public {
        token.mint(address(treasury), 1000e18);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        vm.prank(alice);
        treasury.releaseERC20(address(token), bob, 100e18);
    }

    // ── ETH release ───────────────────────────────────────────────────────────
    function test_releaseETH() public {
        vm.deal(address(treasury), 5 ether);

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Treasury.ETHReleased(bob, 2 ether);

        vm.prank(admin);
        treasury.releaseETH(payable(bob), 2 ether);

        assertEq(bob.balance, 2 ether);
        assertEq(address(treasury).balance, 3 ether);
    }

    function test_releaseETH_revert_notSpender() public {
        vm.deal(address(treasury), 1 ether);
        vm.expectRevert();
        vm.prank(alice);
        treasury.releaseETH(payable(bob), 0.5 ether);
    }

    function test_releaseETH_revert_zeroAddress() public {
        vm.deal(address(treasury), 1 ether);
        vm.expectRevert("Treasury: zero address");
        vm.prank(admin);
        treasury.releaseETH(payable(address(0)), 0.5 ether);
    }

    function test_releaseETH_revert_onRecipientFailure() public {
        EthRejector rejector = new EthRejector();
        vm.deal(address(treasury), 1 ether);

        vm.expectRevert("Treasury: ETH transfer failed");
        vm.prank(admin);
        treasury.releaseETH(payable(address(rejector)), 0.5 ether);
    }

    // ── receive() accepts plain ETH transfers ─────────────────────────────────
    function test_receive_acceptsETH() public {
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        (bool ok,) = address(treasury).call{value: 1.5 ether}("");
        assertTrue(ok);
        assertEq(address(treasury).balance, 1.5 ether);
    }

    // ── Admin can rotate the spender role ─────────────────────────────────────
    function test_admin_canGrantSpenderRole() public {
        // Cache the role bytes before vm.prank — otherwise the SPENDER_ROLE()
        // view call consumes the prank and grantRole runs as the test contract.
        bytes32 spenderRole = treasury.SPENDER_ROLE();

        vm.prank(admin);
        treasury.grantRole(spenderRole, alice);
        assertTrue(treasury.hasRole(spenderRole, alice));

        token.mint(address(treasury), 100e18);
        vm.prank(alice);
        treasury.releaseERC20(address(token), bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }
}
