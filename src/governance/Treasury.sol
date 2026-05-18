// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Treasury is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");

    event ERC20Released(address indexed token, address indexed to, uint256 amount);
    event ETHReleased(address indexed to, uint256 amount);

    constructor(address timelockController) {
        _grantRole(DEFAULT_ADMIN_ROLE, timelockController);
        _grantRole(SPENDER_ROLE, timelockController);
    }

    function releaseERC20(address token, address to, uint256 amount) external onlyRole(SPENDER_ROLE) {
        IERC20(token).safeTransfer(to, amount);
        emit ERC20Released(token, to, amount);
    }

    function releaseETH(address payable to, uint256 amount) external onlyRole(SPENDER_ROLE) {
        require(to != address(0), "Treasury: zero address");
        emit ETHReleased(to, amount);
        // slither-disable-next-line arbitrary-send-eth
        (bool ok,) = to.call{value: amount}("");
        require(ok, "Treasury: ETH transfer failed");
    }

    receive() external payable {}
}
