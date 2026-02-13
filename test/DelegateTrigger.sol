// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {DelegateTrigger} from "src/DelegateTrigger.sol";
import {IERC20, RecoveringDelegate} from "src/RecoveringDelegate.sol";

contract DelegateTriggerTest is Test {
    address internal receiver = makeAddr("RecoveringDelegateTest: receiver");
    address internal executor = makeAddr("RecoveringDelegateTest: executor");
    Vm.Wallet internal userWallet = vm.createWallet("user EOA");

    RecoveringDelegate internal delegate;
    DelegateTrigger internal trigger;
    IERC20 mockErc20 = IERC20(makeAddr("RecoveringDelegateTest: token"));

    function setUp() public {
        delegate = new RecoveringDelegate(receiver);
        trigger = new DelegateTrigger(delegate, userWallet.addr);

        // By default, the mock token reverts.
        vm.mockCallRevert(address(mockErc20), new bytes(0), bytes("unexpected call to mock token"));
    }

    function test_deploymentParameters() external view {
        assertEq(address(trigger.DELEGATE()), address(delegate));
        assertEq(address(trigger.OWNER()), address(userWallet.addr));
    }

    function test_triggerWithdraw_success(uint256 amount) external {
        _prepareTransferMocks(mockErc20, amount, userWallet.addr, receiver);

        vm.signAndAttachDelegation(address(delegate), userWallet.privateKey);
        vm.expectCall(address(mockErc20), abi.encodeCall(IERC20.transfer, (receiver, amount)));
        trigger.triggerWithdraw(mockErc20);
    }

    function test_triggerWithdraw_revertsWithNoDelegate(uint256 amount) external {
        _prepareTransferMocks(mockErc20, amount, userWallet.addr, receiver);

        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateTrigger.UnexpectedDelegate.selector, delegationCode(address(delegate)), hex""
            )
        );
        trigger.triggerWithdraw(mockErc20);
    }

    function test_triggerWithdraw_revertsWithBadDelegate(uint256 amount) external {
        address anotherDelegate = makeAddr("another delegate");
        _prepareTransferMocks(mockErc20, amount, userWallet.addr, receiver);

        vm.signAndAttachDelegation(anotherDelegate, userWallet.privateKey);
        vm.expectRevert(
            abi.encodeWithSelector(
                DelegateTrigger.UnexpectedDelegate.selector,
                delegationCode(address(delegate)),
                delegationCode(anotherDelegate)
            )
        );
        trigger.triggerWithdraw(mockErc20);
    }

    function _prepareTransferMocks(IERC20 token, uint256 amount, address user, address _receiver) internal {
        vm.mockCall(address(token), abi.encodeCall(IERC20.balanceOf, (user)), abi.encode(amount));
        vm.mockCall(address(token), abi.encodeCall(IERC20.transfer, (_receiver, amount)), abi.encode(true));
    }

    function delegationCode(address _delegate) internal pure returns (bytes memory) {
        return abi.encodePacked(hex"ef0100", _delegate);
    }
}
