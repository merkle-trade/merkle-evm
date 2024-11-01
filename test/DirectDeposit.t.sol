// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ITokenBridge} from "LayerZero-Aptos-Contract/apps/bridge-evm/contracts/interfaces/ITokenBridge.sol";
import {DirectDeposit, DirectDepositConfig} from "../src/DirectDeposit.sol";
import {DirectDepositFactory} from "../src/DirectDepositFactory.sol";

contract DirectDepositTest is Test {
    IERC20 constant usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ITokenBridge constant aptosBridge = ITokenBridge(0x50002CdFe7CCb0C41F519c6Eb0653158d11cd907);

    DirectDepositConfig cfg;
    DirectDeposit impl;
    DirectDepositFactory factory;

    DirectDeposit directDeposit;
    address swapTarget;
    address keeper;
    address rescuer;
    address user;
    address admin;

    function setUp() public {
        uint256 mainnetForkBlock = 20147733;
        vm.createSelectFork(vm.rpcUrl("mainnet"), mainnetForkBlock);

        keeper = makeAddr("keeper");
        rescuer = makeAddr("rescuer");
        user = makeAddr("user");
        admin = makeAddr("admin");

        deal(keeper, 1 ether);

        swapTarget = address(new SimpleSwap(usdt, usdc));
        deal(address(usdc), address(swapTarget), 1_000_000);

        cfg = new DirectDepositConfig();
        cfg.initialize(aptosBridge, usdc, address(swapTarget), keeper, rescuer, admin);
        impl = new DirectDeposit(cfg);
        factory = new DirectDepositFactory(address(impl));

        bytes32 aptosAddress = bytes32(uint256(0x1));
        uint256 nonce = uint256(0x2);
        directDeposit = factory.deploy(aptosAddress, nonce);
    }

    function test_InitializeOnlyOnce() public {
        bytes32 aptosAddress = bytes32(uint256(0x3));
        uint256 nonce = uint256(0x4);

        DirectDeposit newDirectDeposit = factory.deploy(aptosAddress, nonce);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.AlreadyInitialized.selector));
        newDirectDeposit.initialize(aptosAddress);
    }

    function test_SetMaxFee() public {
        vm.prank(admin);
        cfg.setMaxFee(100);
        assertEq(cfg.maxFee(), 100);
    }

    function test_SetFee_OnlyAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.UnauthorizedAccount.selector, user));
        cfg.setMaxFee(100);
    }

    function test_SwapAndSendToAptos() public {
        // Setup
        uint256 balanceBefore = keeper.balance;

        uint256 fromAmount = 1000;
        uint256 toAmount = 999; // 0.999 * fromAmount
        bytes memory swapBytes = abi.encodeWithSignature("swap(uint256,uint256)", fromAmount, toAmount);

        deal(address(usdt), address(directDeposit), fromAmount);
        deal(address(usdc), address(swapTarget), toAmount);

        // Set a fee
        vm.prank(admin);
        cfg.setMaxFee(10);

        // Call swapAndSendToAptos
        vm.startPrank(keeper);
        (uint256 nativeFee,) = directDeposit.quoteForSend();
        uint256 gasBefore = gasleft();
        directDeposit.swapAndSendToAptos{value: nativeFee + 1234}(usdt, fromAmount, toAmount, 9, swapBytes);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for swapAndSendToAptos:", gasUsed);

        // Verify the fee transfer
        assertEq(usdc.balanceOf(keeper), 9, "Keeper should receive the fee");
        assertEq(keeper.balance, balanceBefore - nativeFee, "Surplus ETH should be refunded");

        vm.stopPrank();
    }

    function test_SwapAndSendToAptos_SwapError() public {
        vm.startPrank(keeper);

        uint256 fromAmount = 1000;
        uint256 toAmount = 990;
        bytes memory swapBytes = abi.encodeWithSignature("swap(uint256,uint256)", fromAmount, toAmount);

        deal(address(usdt), address(directDeposit), fromAmount);

        (uint256 nativeFee,) = directDeposit.quoteForSend();
        vm.expectRevert(DirectDeposit.SwapError.selector);
        directDeposit.swapAndSendToAptos{value: nativeFee}(usdt, fromAmount, toAmount + 1, 0, swapBytes);

        vm.stopPrank();
    }

    function test_SwapAndSendToAptos_OnlyKeeper() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.UnauthorizedAccount.selector, user));
        directDeposit.swapAndSendToAptos(usdt, 1000, 999, 100, bytes(""));
        vm.stopPrank();
    }

    function test_SendToAptos() public {
        // Setup
        uint256 balanceBefore = keeper.balance;

        uint256 amount = 1000;
        uint256 fee = 9;
        deal(address(usdc), address(directDeposit), amount);

        // Call sendToAptos
        vm.startPrank(keeper);
        (uint256 nativeFee,) = directDeposit.quoteForSend();
        uint256 gasBefore = gasleft();
        directDeposit.sendToAptos{value: nativeFee + 1234}(amount, fee);
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for sendToAptos:", gasUsed);

        // Verify the fee transfer
        assertEq(usdc.balanceOf(address(keeper)), fee, "Keeper should receive the fee");
        assertEq(keeper.balance, balanceBefore - nativeFee, "Surplus native should be refunded");
    }

    function test_SendToAptos_OnlyKeeper() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.UnauthorizedAccount.selector, user));
        directDeposit.sendToAptos(1000, 100);
        vm.stopPrank();
    }

    function test_RescueERC20() public {
        // Setup: Transfer some USDT to the contract
        uint256 amount = 1000;
        deal(address(usdt), address(directDeposit), amount);

        // Attempt rescue from non-rescuer address
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.UnauthorizedAccount.selector, keeper));
        directDeposit.rescue(usdt, user);

        // Rescue USDT
        vm.prank(rescuer);
        directDeposit.rescue(usdt, user);

        // Verify USDT was transferred to rescueRecipient
        assertEq(usdt.balanceOf(user), amount);
        assertEq(usdt.balanceOf(address(directDeposit)), 0);
    }

    function test_RescueETH() public {
        // Setup: Send some ETH to the contract
        uint256 amount = 1 ether;
        vm.deal(address(directDeposit), amount);

        // Attempt rescue from non-rescuer address
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.UnauthorizedAccount.selector, keeper));
        directDeposit.rescue(IERC20(address(0)), user);

        // Rescue ETH
        uint256 balanceBefore = user.balance;
        vm.prank(rescuer);
        directDeposit.rescue(IERC20(address(0)), user);

        // Verify ETH was transferred to user
        assertEq(user.balance - balanceBefore, amount);
        assertEq(address(directDeposit).balance, 0);
    }

    function test_RescueNothingToRescue() public {
        vm.prank(rescuer);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.RescueFailed.selector));
        directDeposit.rescue(usdt, user);

        vm.prank(rescuer);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.RescueFailed.selector));
        directDeposit.rescue(IERC20(address(0)), user);
    }

    function test_RescueFailedETH() public {
        // Setup: Send some ETH to the contract
        uint256 amount = 1 ether;
        vm.deal(address(directDeposit), amount);

        // Create a contract that rejects ETH transfers
        address payable rejectingContract = payable(address(new RejectETH()));

        // Update the rescuer address to the rejecting contract
        DirectDepositConfig newCfg = new DirectDepositConfig();
        newCfg.initialize(aptosBridge, usdc, address(swapTarget), keeper, rejectingContract, admin);
        DirectDeposit newDirectDeposit = new DirectDeposit(newCfg);
        vm.deal(address(newDirectDeposit), amount);

        // Attempt to rescue ETH, which should fail
        vm.prank(rejectingContract);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.RescueFailed.selector));
        newDirectDeposit.rescue(IERC20(address(0)), rejectingContract);
    }

    function test_RescueTimelock() public {
        // Setup: Deploy a RescueTimelock contract
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = rescuer;
        executors[0] = rescuer;
        uint256 delay = 10 days;
        TimelockController timelock = new TimelockController(delay, proposers, executors, rescuer);

        // Deploy a DirectDeposit contract with the timelock as the rescuer
        DirectDepositConfig newCfg = new DirectDepositConfig();
        newCfg.initialize(aptosBridge, usdc, address(swapTarget), keeper, address(timelock), admin);
        DirectDeposit newDirectDeposit = new DirectDeposit(newCfg);
        vm.deal(address(newDirectDeposit), 1 ether);

        // Attempt to rescue ETH, which should fail
        vm.prank(rescuer);
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.UnauthorizedAccount.selector, rescuer));
        newDirectDeposit.rescue(IERC20(address(0)), user);

        // Schedule ETH rescue
        vm.prank(rescuer);
        timelock.schedule(
            address(newDirectDeposit),
            0,
            abi.encodeWithSelector(DirectDeposit.rescue.selector, IERC20(address(0)), user),
            bytes32(0),
            bytes32(0),
            delay
        );

        // Attempt to rescue ETH immediately after scheduling, which should fail due to timelock
        vm.prank(rescuer);
        vm.expectPartialRevert(TimelockController.TimelockUnexpectedOperationState.selector);
        timelock.execute(
            address(newDirectDeposit),
            0,
            abi.encodeWithSelector(DirectDeposit.rescue.selector, IERC20(address(0)), user),
            bytes32(0),
            bytes32(0)
        );

        // Wait for the timelock to pass
        vm.warp(block.timestamp + delay);

        // Execute ETH rescue
        uint256 beforeBalance = user.balance;
        vm.prank(rescuer);
        timelock.execute(
            address(newDirectDeposit),
            0,
            abi.encodeWithSelector(DirectDeposit.rescue.selector, IERC20(address(0)), user),
            bytes32(0),
            bytes32(0)
        );

        // Verify ETH was transferred to user
        assertEq(user.balance - beforeBalance, 1 ether);
        assertEq(address(newDirectDeposit).balance, 0);
    }

    function test_SendToAptos_FeeTooHigh() public {
        // Setup
        uint256 amount = 1000;
        uint256 maxFee = 10;
        uint256 fee = 11;
        deal(address(usdc), address(directDeposit), amount);

        // Set a fee
        vm.prank(admin);
        cfg.setMaxFee(maxFee);

        // Call sendToAptos
        vm.startPrank(keeper);
        (uint256 nativeFee,) = directDeposit.quoteForSend();
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.FeeTooHigh.selector));
        directDeposit.sendToAptos{value: nativeFee + 1234}(amount, fee);
    }

    function test_SwapAndSendToAptos_FeeTooHigh() public {
        // Setup
        uint256 fromAmount = 1000;
        uint256 toAmount = 999; // 0.999 * fromAmount
        uint256 maxFee = 10;
        uint256 fee = 11;
        bytes memory swapBytes = abi.encodeWithSignature("swap(uint256,uint256)", fromAmount, toAmount);

        deal(address(usdt), address(directDeposit), fromAmount);
        deal(address(usdc), address(swapTarget), toAmount);

        // Set a fee
        vm.prank(admin);
        cfg.setMaxFee(maxFee);

        // Call swapAndSendToAptos
        vm.startPrank(keeper);
        (uint256 nativeFee,) = directDeposit.quoteForSend();
        vm.expectRevert(abi.encodeWithSelector(DirectDeposit.FeeTooHigh.selector));
        directDeposit.swapAndSendToAptos{value: nativeFee + 1234}(usdt, fromAmount, toAmount, fee, swapBytes);
    }
}

contract SimpleSwap {
    using SafeERC20 for IERC20;

    IERC20 public immutable A;
    IERC20 public immutable B;

    constructor(IERC20 _a, IERC20 _b) {
        A = _a;
        B = _b;
    }

    function swap(uint256 fromAmount, uint256 toAmount) external {
        A.safeTransferFrom(msg.sender, address(this), fromAmount);
        B.safeTransfer(msg.sender, toAmount);
    }
}

// Helper contract that rejects ETH transfers
contract RejectETH {
    receive() external payable {
        revert("ETH transfer rejected");
    }
}
