// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";

import {DelegateTrigger} from "src/DelegateTrigger.sol";
import {RecoveringDelegate} from "src/RecoveringDelegate.sol";

contract DeployAll is Script {
    RecoveringDelegate public delegate;
    DelegateTrigger public trigger;

    function run(address receiver, address owner) public {
        console.log("Deploying on chain:", block.chainid);

        console.log("Using receiver address:", receiver);

        vm.broadcast();
        delegate = new RecoveringDelegate{salt: bytes32(0)}(receiver);

        console.log("Using owner address:", owner);
        console.log("Using deployed delegate address:", address(delegate));

        vm.broadcast();
        trigger = new DelegateTrigger{salt: bytes32(0)}(delegate, owner);

        console.log("Deployed trigger address:", address(trigger));
    }
}
