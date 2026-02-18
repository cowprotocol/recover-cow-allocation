// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8;

import {Script} from "forge-std/Script.sol";

import {RecoveringDelegate} from "src/RecoveringDelegate.sol";

contract RecoveringDelegateScript is Script {
    RecoveringDelegate public delegate;

    function run(address receiver) public {
        vm.broadcast();
        delegate = new RecoveringDelegate{salt: bytes32(0)}(receiver);
    }
}
