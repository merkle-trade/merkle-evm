// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ITokenBridge} from "LayerZero-Aptos-Contract/apps/bridge-evm/contracts/interfaces/ITokenBridge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DirectDepositFactory} from "../src/DirectDepositFactory.sol";
import {DirectDeposit, DirectDepositConfig} from "../src/DirectDeposit.sol";

contract DirectDepositFactoryTest is Test {
    DirectDepositConfig cfg;
    DirectDeposit impl;
    DirectDepositFactory factory;

    ITokenBridge lzTokenBridge;
    address swapTarget;
    address keeper;
    address rescuer;
    address admin;

    function setUp() public {
        lzTokenBridge = ITokenBridge(makeAddr("lzTokenBridge"));
        swapTarget = makeAddr("swapTarget");
        keeper = makeAddr("keeper");
        rescuer = makeAddr("rescuer");
        admin = makeAddr("admin");

        cfg = new DirectDepositConfig();
        cfg.initialize(lzTokenBridge, IERC20(address(0)), swapTarget, keeper, rescuer, admin);
        impl = new DirectDeposit(cfg);
        factory = new DirectDepositFactory(address(impl));
    }

    function test_Deploy() public {
        bytes32 aptosAddress = bytes32(uint256(0x3));
        uint256 nonce = uint256(0x4);

        uint256 gasBefore = gasleft();
        DirectDeposit newDirectDeposit = factory.deploy(aptosAddress, nonce);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for DirectDeposit deployment:", gasUsed);
        assertLt(gasUsed, 110000, "Gas used for deployment should be minimal");

        // Verify the new direct deposit contract was deployed correctly

        address predictedAddress = factory.getAddress(aptosAddress, nonce);
        assertEq(predictedAddress, address(newDirectDeposit));

        // Verify the new direct deposit contract was initialized correctly

        assertEq(newDirectDeposit.aptosAddress(), aptosAddress);
    }

    function test_InvalidAddress() public {
        bytes32 aptosAddress = bytes32(0);
        uint256 nonce = uint256(0x4);

        vm.expectRevert(abi.encodeWithSelector(DirectDepositFactory.InvalidAddress.selector));
        factory.deploy(aptosAddress, nonce);
    }
}
