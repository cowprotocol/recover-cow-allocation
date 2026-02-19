// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";

import {DelegationGuard} from "src/DelegationGuard.sol";
import {RecoveringDelegate} from "src/RecoveringDelegate.sol";

contract DeployAll is Script {
    RecoveringDelegate public delegate;
    DelegationGuard public guard;

    bytes32 public constant SALT = bytes32(uint256(0));

    function run(address receiver, address owner) public {
        console.log("Deploying on chain:", block.chainid);

        console.log("Using receiver address:", receiver);

        vm.broadcast();
        delegate = new RecoveringDelegate{salt: SALT}(receiver);

        console.log("Using owner address:", owner);
        console.log("Using deployed delegate address:", address(delegate));

        vm.broadcast();
        guard = new DelegationGuard{salt: SALT}(delegate, owner);

        console.log("Deployed guard address:", address(guard));
    }
}
