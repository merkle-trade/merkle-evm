// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {HelloWorld} from "../src/HelloWorld.sol";

contract HelloWorldTest is Test {
    function test_DeploymentGasCost() public {
        uint256 gasBefore = gasleft();
        new HelloWorld();
        uint256 gasAfter = gasleft();

        uint256 gasCost = gasBefore - gasAfter;
        console.log("Deployment gas cost:", gasCost);

        assertLt(gasCost, 60000, "Deployment gas cost is too high");
    }
}
