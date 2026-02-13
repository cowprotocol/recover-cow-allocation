// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {RecoveringDelegate} from "src/RecoveringDelegate.sol";

/// @title DelegateTrigger
/// @notice A contract exposing a function that lets anyone call the owner.
/// If the owner sports the expected DELEGATE as an EIP-7702 delegate, then
/// the transaction goes through and the `withdraw` function is called.
/// If the delegate isn't set, then the transaction reverts.
/// This behavior is useful in a Safe batch transaction that's only supposed to
/// succeed if the withdrawal is successful.
contract DelegateTrigger {
    /// @notice The contract that is expected to be set as an EIP-7702 delegate
    /// at the OWNER address.
    RecoveringDelegate public immutable DELEGATE;
    /// @notice The contract that is expected to be set as an EIP-7702 delegate
    /// at the OWNER address.
    address public immutable OWNER;

    error UnexpectedDelegate(bytes expectedCode, bytes actualCode);

    constructor(RecoveringDelegate _delegate, address _owner) {
        DELEGATE = _delegate;
        OWNER = _owner;
    }

    /// @notice If OWNER has the right delegate, it triggers the withdraw of
    /// the input token from the ONWER. Otherwise, it reverts.
    /// @param token The token to withdraw.
    function triggerWithdraw(IERC20 token) external {
        assertHasExpectedDelegate(OWNER, DELEGATE);
        RecoveringDelegate(OWNER).withdraw(token);
    }

    function assertHasExpectedDelegate(address _owner, RecoveringDelegate _delegate) internal view {
        bytes memory actualCode = _owner.code;
        // This is the delegation indicator as per EIP-7702
        // https://eips.ethereum.org/EIPS/eip-7702#abstract
        bytes memory expectedCode = abi.encodePacked(hex"ef0100", _delegate);
        require(
            keccak256(actualCode) == keccak256(expectedCode),
            UnexpectedDelegate({expectedCode: expectedCode, actualCode: actualCode})
        );
    }
}
