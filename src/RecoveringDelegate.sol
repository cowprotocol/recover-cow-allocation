// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RecoveringDelegate
/// @notice This contract is used to recover ERC20 tokens from an
/// externally-owned account. The user deploys the contract and specifies a
/// trusted address to receive the funds as a constructor parameter.
/// Then, the user's externally-owned account delegates this contract with a
/// type-4 transaction (see EIP-7702).
/// After that, anyone can call `withdraw` and move any ERC20 token from the
/// user's externally-owned account to the specified address.
contract RecoveringDelegate {
    using SafeERC20 for IERC20;

    /// @notice The address who will receive the funds
    address public immutable RECEIVER;

    constructor(address _receiver) {
        RECEIVER = _receiver;
    }

    /// @notice This function withdraws the entire balance of the input token
    /// from this contract to the immutable RECEIVER.
    /// @param token The token to withdraw
    function withdraw(IERC20 token) external {
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(RECEIVER, balance);
    }
}
