// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ═════════════════════════════════════════════════════════════════════════════
// CASE STUDY 1 — Reentrancy
//
// Vulnerability: ETH balance is zeroed AFTER the external call, so an
// attacker's receive() can re-enter withdraw() and drain the vault.
//
// Fix: zero the balance BEFORE the external call (Checks-Effects-Interactions)
//      and wrap with ReentrancyGuard as a belt-and-suspenders guard.
// ═════════════════════════════════════════════════════════════════════════════

/// @dev VULNERABLE — interaction precedes effect
contract VulnerableEthVault {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        // BUG: external call before state update — reentrancy possible
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        balances[msg.sender] = 0; // ← effect AFTER interaction
    }

    receive() external payable {}
}

/// @dev FIXED — CEI pattern + ReentrancyGuard
contract SafeEthVault is ReentrancyGuard {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "No balance");
        balances[msg.sender] = 0; // ← effect BEFORE interaction (CEI)
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    receive() external payable {}
}

/// @dev Attacker that re-enters withdraw() in its receive() hook
contract ReentrancyAttacker {
    VulnerableEthVault public immutable target;
    uint256 public attackAmount;

    constructor(address payable _target) {
        target = VulnerableEthVault(_target);
    }

    function attack() external payable {
        attackAmount = msg.value;
        target.deposit{value: msg.value}();
        target.withdraw();
    }

    receive() external payable {
        // Re-enter as long as the vault still holds enough funds
        if (address(target).balance >= attackAmount) {
            target.withdraw();
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// CASE STUDY 2 — Access Control
//
// Vulnerability: a privileged admin function has no access guard, so any
// caller can set themselves as owner and drain protocol funds.
//
// Fix: gate every privileged function with OpenZeppelin Ownable (or
//      AccessControl).
// ═════════════════════════════════════════════════════════════════════════════

/// @dev VULNERABLE — setFeeRecipient has no access guard
contract VulnerableProtocol {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    // BUG: anyone can call this and become the owner
    function setOwner(address newOwner) external {
        owner = newOwner; // ← missing onlyOwner check
    }

    function collectFees(address payable recipient, uint256 amount) external {
        require(msg.sender == owner, "Not owner");
        require(address(this).balance >= amount, "Insufficient balance");
        (bool ok,) = recipient.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    receive() external payable {}
}

/// @dev FIXED — uses OpenZeppelin Ownable throughout
contract SafeProtocol is Ownable {
    constructor() Ownable(msg.sender) {}

    // FIXED: onlyOwner prevents unauthorised ownership transfer
    function transferOwnershipSafe(address newOwner) external onlyOwner {
        transferOwnership(newOwner);
    }

    function collectFees(address payable recipient, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool ok,) = recipient.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    receive() external payable {}
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS — Case Study 1: Reentrancy
// ═════════════════════════════════════════════════════════════════════════════

contract ReentrancySecurityTest is Test {
    VulnerableEthVault internal vulnerable;
    SafeEthVault internal safe;

    address internal alice   = makeAddr("alice");
    address internal attAddr = makeAddr("attacker");

    function setUp() public {
        vulnerable = new VulnerableEthVault();
        safe       = new SafeEthVault();

        // Alice is an innocent depositor providing liquidity in both vaults.
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vulnerable.deposit{value: 10 ether}();

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        safe.deposit{value: 10 ether}();
    }

    /// @dev BEFORE FIX: reentrancy attack succeeds, vault is drained
    function test_reentrancy_attack_drains_vulnerable_vault() public {
        vm.deal(attAddr, 1 ether);

        ReentrancyAttacker evil = new ReentrancyAttacker(payable(address(vulnerable)));
        vm.prank(attAddr);
        evil.attack{value: 1 ether}();

        // Attacker's contract holds more than its initial 1 ETH deposit
        assertGt(address(evil).balance, 1 ether, "Attacker must have stolen funds");
        // Vault was drained below what Alice deposited
        assertLt(address(vulnerable).balance, 10 ether, "Vault should be partially or fully drained");
    }

    /// @dev AFTER FIX: reentrant withdraw reverts on the safe vault
    function test_reentrancy_attack_fails_on_safe_vault() public {
        vm.deal(attAddr, 1 ether);

        // We simulate the pattern manually: deposit then withdraw.
        // Any reentrant call will be blocked by nonReentrant.
        vm.startPrank(attAddr);
        safe.deposit{value: 1 ether}();
        safe.withdraw();
        vm.stopPrank();

        // Alice's 10 ETH is untouched — attacker only got back their own 1 ETH
        assertEq(address(safe).balance, 10 ether, "Alice funds must remain intact");
    }

    /// @dev Normal deposit → withdraw flow works correctly on the safe vault
    function test_safe_vault_normal_flow() public {
        address bob = makeAddr("bob");
        vm.deal(bob, 5 ether);

        vm.startPrank(bob);
        safe.deposit{value: 5 ether}();
        assertEq(safe.balances(bob), 5 ether, "Balance tracked correctly");

        uint256 before = bob.balance;
        safe.withdraw();
        assertEq(bob.balance, before + 5 ether, "Bob receives ETH on withdrawal");
        assertEq(safe.balances(bob), 0, "Balance zeroed after withdrawal");
        vm.stopPrank();
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TESTS — Case Study 2: Access Control
// ═════════════════════════════════════════════════════════════════════════════

contract AccessControlSecurityTest is Test {
    VulnerableProtocol internal vulnerable;
    SafeProtocol       internal safe;

    address internal deployer = makeAddr("deployer");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        vm.startPrank(deployer);
        vulnerable = new VulnerableProtocol();
        safe       = new SafeProtocol();
        vm.stopPrank();

        // Fund both protocols as if they hold protocol fees.
        vm.deal(address(vulnerable), 5 ether);
        vm.deal(address(safe),       5 ether);
    }

    /// @dev BEFORE FIX: attacker hijacks owner via unguarded setOwner
    function test_accessControl_attacker_hijacks_vulnerable_ownership() public {
        assertNotEq(vulnerable.owner(), attacker, "Attacker not owner before attack");

        vm.prank(attacker);
        vulnerable.setOwner(attacker); // ← no revert — vulnerability confirmed

        assertEq(vulnerable.owner(), attacker, "Attacker became owner");

        // Attacker can now drain all fees
        uint256 balBefore = attacker.balance;
        vm.prank(attacker);
        vulnerable.collectFees(payable(attacker), 5 ether);

        assertGt(attacker.balance, balBefore, "Attacker drained protocol funds");
    }

    /// @dev AFTER FIX: unauthorised setOwner call reverts
    function test_accessControl_safe_rejects_ownership_hijack() public {
        assertEq(safe.owner(), deployer, "Deployer is initial owner");

        vm.prank(attacker);
        vm.expectRevert(); // OZ Ownable reverts with OwnableUnauthorizedAccount
        safe.transferOwnershipSafe(attacker);

        // Ownership unchanged
        assertEq(safe.owner(), deployer, "Ownership must remain with deployer");
    }

    /// @dev Non-owner cannot collect fees on the safe protocol
    function test_accessControl_nonOwner_cannot_collect_fees() public {
        vm.prank(attacker);
        vm.expectRevert();
        safe.collectFees(payable(attacker), 1 ether);

        // Protocol balance unchanged
        assertEq(address(safe).balance, 5 ether, "Protocol balance must be unchanged");
    }

    /// @dev Legitimate owner can collect fees on the safe protocol
    function test_accessControl_owner_can_collect_fees() public {
        uint256 before = deployer.balance;

        vm.prank(deployer);
        safe.collectFees(payable(deployer), 1 ether);

        assertEq(deployer.balance, before + 1 ether, "Owner receives fees");
        assertEq(address(safe).balance, 4 ether, "Protocol balance decremented correctly");
    }
}
