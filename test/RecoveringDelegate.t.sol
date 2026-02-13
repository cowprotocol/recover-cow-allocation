// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {IERC20, RecoveringDelegate, SafeERC20} from "src/RecoveringDelegate.sol";

contract RecoveringDelegateTest is Test {
    address internal receiver = makeAddr("RecoveringDelegateTest: receiver");
    address internal executor = makeAddr("RecoveringDelegateTest: executor");
    Vm.Wallet internal userWallet = vm.createWallet("user EOA");

    RecoveringDelegate internal delegate;
    IERC20 mockErc20 = IERC20(makeAddr("RecoveringDelegateTest: token"));

    function setUp() external {
        delegate = new RecoveringDelegate(receiver);

        vm.signAndAttachDelegation(address(delegate), userWallet.privateKey);

        // By default, the mock token reverts.
        vm.mockCallRevert(address(mockErc20), new bytes(0), bytes("unexpected call to mock token"));
    }

    function test_deploymentParameters() external view {
        assertEq(delegate.RECEIVER(), receiver);
    }

    function test_withdraw_callsTransferOnSuccess(uint256 amount) external {
        vm.mockCall(address(mockErc20), abi.encodeCall(IERC20.balanceOf, (userWallet.addr)), abi.encode(amount));
        vm.mockCall(address(mockErc20), abi.encodeCall(IERC20.transfer, (receiver, amount)), abi.encode(true));

        vm.expectCall(address(mockErc20), abi.encodeCall(IERC20.transfer, (receiver, amount)));
        RecoveringDelegate(userWallet.addr).withdraw(mockErc20);
    }

    function test_withdraw_revertsIfTokenReturnsFalse(uint256 amount) external {
        vm.mockCall(address(mockErc20), abi.encodeCall(IERC20.balanceOf, (userWallet.addr)), abi.encode(amount));
        vm.mockCall(address(mockErc20), abi.encodeCall(IERC20.transfer, (receiver, amount)), abi.encode(false));

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, mockErc20));
        RecoveringDelegate(userWallet.addr).withdraw(mockErc20);
    }
}
