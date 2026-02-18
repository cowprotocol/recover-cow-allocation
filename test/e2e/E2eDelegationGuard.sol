// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";
import {AllocationModule} from "lib/team-cow-allocation/src/contracts/AllocationModule.sol";
import {ModuleController} from "lib/team-cow-allocation/src/contracts/vendored/ModuleController.sol";

import {DelegationGuard} from "src/DelegationGuard.sol";
import {IERC20, RecoveringDelegate} from "src/RecoveringDelegate.sol";

contract E2eDelegationGuardTest is Test {
    // MAINNET FORK CONSTANTS
    uint64 internal constant MAINNET_FORK_BLOCK = 24449552;
    // See `lib/team-cow-allocation/networks.json`
    AllocationModule internal constant ALLOCATION_MODULE = AllocationModule(0x582A254713b65c140840ade25A692fBe2610682d);
    // See `lib/team-cow-allocation/src/ts/constants.ts`
    ModuleController internal constant TEAM_ALLOCATION_SAFE =
        ModuleController(0xca07EaA4253638D286caD71CBcEec11803F2709A);
    // This is the most recent user I found that claimed tokens through the
    // allocation module and used an EOA to store funds.
    address internal constant LIVE_USER = 0xf3e9BE5cc045Fdf2C4B5599446cdffC3c283B83B;
    IERC20 internal cow;

    address internal receiver = makeAddr("E2EDelegationGuardTest: receiver");
    address internal executor = makeAddr("E2EDelegationGuardTest: executor");
    // I wish it was possible to set an EIP-7702 delegation without knowing the
    // private key, but this doesn't seem to be possible and so we need to use
    // an independent wallet.
    Vm.Wallet internal userWallet = vm.createWallet("user EOA");

    function setUp() public {
        string memory forkRpcUrl = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(forkRpcUrl);
        vm.rollFork(MAINNET_FORK_BLOCK);

        cow = IERC20(address(ALLOCATION_MODULE.cow()));
    }

    function test_noUserCanClaim() external {
        // At MAINNET_FORK_BLOCK, the module is disabled, so no user can claim.
        vm.prank(LIVE_USER);
        // https://github.com/safe-fndn/safe-smart-account/blob/bf943f80fec5ac647159d26161446ac5d716a294/docs/error_codes.md#module-management-related
        vm.expectRevert(bytes("GS104")); // "Method can only be called from an enabled module"
        ALLOCATION_MODULE.claimAllCow();
    }

    function test_fundRecovery_success() external {
        // We test how the contracts in this repo are expected to be used to
        // recover funds. Settings:
        // - The user has a known-good address (receiver) and a possibly
        //   compromised wallet (userWallet).
        // - A user has some COW vesting in the team allocation module.
        // - The allocation module is disabled.
        // Then, the recovery approach is the following:
        // - The contracts in this repo are deployed for the user wallet and
        //   receiver.
        // - The team allocation Safe executes the following transactions in the
        //   same batch:
        //   1. Enable module
        //   2. Stop user allocation
        //   3. trigger the deployed `DelegationGuard` to withdraw the funds to
        //      the receiver.
        //   For security, these functions should be sent in the same call of
        //   `execute`, so that the module isn't enabled if the trigger fails.
        //   However, we execute each transaction one-by-one for ease of
        //   testing.

        // (Ideally we'd use an existing claim, but it doesn't seem to be
        // possible to set a 7702 delegate for an address with an unknown
        // private key.)
        uint32 claimStart = uint32(block.timestamp) - 10 weeks;
        uint32 claimDuration = 40 weeks;
        uint96 fullClaimAmount = 42 ether;
        vm.prank(address(TEAM_ALLOCATION_SAFE));
        ALLOCATION_MODULE.addClaim(userWallet.addr, claimStart, claimDuration, fullClaimAmount);

        assertEq(
            TEAM_ALLOCATION_SAFE.isModuleEnabled(address(ALLOCATION_MODULE)), false, "Module is expected to be disabled"
        );

        RecoveringDelegate delegate = new RecoveringDelegate(receiver);
        DelegationGuard guard = new DelegationGuard(delegate, userWallet.addr);

        // We confirm that a claim is available.
        vm.warp(claimStart + claimDuration / 2); // half of the vesting period
        assertEq(ALLOCATION_MODULE.claimableCow(userWallet.addr), 21 ether, "Unexpected amount");

        // - Tx 1: enable module
        vm.prank(address(TEAM_ALLOCATION_SAFE));
        TEAM_ALLOCATION_SAFE.enableModule(address(ALLOCATION_MODULE));

        // Three quarter of the claim period has passed, to get round numbers.
        vm.warp(claimStart + claimDuration * 3 / 4);
        uint256 cowClaim = 31.5 ether;

        // - Tx 2: stop claim
        vm.prank(address(TEAM_ALLOCATION_SAFE));
        vm.expectEmit(address(cow));
        emit IERC20.Transfer(address(TEAM_ALLOCATION_SAFE), userWallet.addr, cowClaim);
        ALLOCATION_MODULE.stopClaim(userWallet.addr);

        // - Tx 3: guard withdrawal
        vm.prank(address(TEAM_ALLOCATION_SAFE));
        vm.expectEmit(address(cow));
        emit IERC20.Transfer(userWallet.addr, receiver, cowClaim);
        vm.signAndAttachDelegation(address(delegate), userWallet.privateKey);
        guard.triggerWithdraw(cow);

        assertEq(cow.balanceOf(userWallet.addr), 0, "No funds should remain in the user EOA");
        assertEq(cow.balanceOf(receiver), cowClaim, "Claimed funds should be sent to the receiver");
        vm.warp(claimStart + claimDuration);
        assertEq(ALLOCATION_MODULE.claimableCow(userWallet.addr), 0, "The user should be stopped");
    }

    function test_fundRecovery_revertsWithNoDelegate() external {
        // Ideally we'd test the entire process in a single `execTransaction`,
        // but we don't do that for simplicity.
        // We just confirm the fact that the safe reverts if triggering the
        // withdrawal.

        RecoveringDelegate delegate = new RecoveringDelegate(receiver);
        DelegationGuard guard = new DelegationGuard(delegate, userWallet.addr);

        vm.prank(address(TEAM_ALLOCATION_SAFE));

        vm.expectRevert(
            abi.encodeWithSelector(DelegationGuard.UnexpectedDelegate.selector, delegationCode(delegate), hex"")
        );
        guard.triggerWithdraw(cow);
    }

    function delegationCode(RecoveringDelegate _delegate) internal pure returns (bytes memory) {
        return abi.encodePacked(hex"ef0100", _delegate);
    }
}
