// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {SwapBridge} from "../src/SwapBridge.sol";

contract SwapBridgeTest is Test {
    IERC20 constant usdt = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address constant fromUser = 0x8558FE88F8439dDcd7453ccAd6671Dfd90657a32; // some rich guy with 8-digit USDT blance
    address constant lzTokenBridge = 0x50002CdFe7CCb0C41F519c6Eb0653158d11cd907;
    address constant paraswapAugustusSwapper = 0x6A000F20005980200259B80c5102003040001068;

    address deployer;
    SwapBridge swapBridge;

    function setUp() public {
        uint256 mainnetForkBlock = 20147733;
        vm.createSelectFork(vm.rpcUrl("mainnet"), mainnetForkBlock);

        deployer = makeAddr("deployer");
        assertEq(deployer, 0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946);

        startHoax(deployer);
        swapBridge = new SwapBridge(deployer);
        swapBridge.initialize(lzTokenBridge, paraswapAugustusSwapper);
        vm.stopPrank();
        assertEq(address(swapBridge), 0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b);

        // fromUser
        assertGt(usdt.balanceOf(fromUser), 100_000_000_000);
        assertEq(usdc.balanceOf(fromUser), 0);
    }

    function test_InitializeOnlyOnce() public {
        swapBridge = new SwapBridge(deployer);
        vm.prank(deployer);
        swapBridge.initialize(address(0x1), address(0x1));
        vm.expectRevert(SwapBridge.AlreadyInitialized.selector);
        vm.prank(deployer);
        swapBridge.initialize(address(0x1), address(0x1));
    }

    function test_SwapAndSendToAptos_ParaSwap() public {
        swapBridge.approveMax(usdc, lzTokenBridge);
        swapBridge.approveMax(usdt, paraswapAugustusSwapper);
        (uint256 nativeFee,) = swapBridge.quoteForSend();

        startHoax(fromUser);
        uint256 prevBalance = address(fromUser).balance;
        SafeERC20.safeIncreaseAllowance(usdt, address(swapBridge), 1_000_000_000);
        swapBridge.swapAndSendToAptos{value: nativeFee + 100_000}(
            usdt,
            1_000_000_000, // 1000 USDT
            usdc,
            990_000_000,
            hex"01",
            hex"876a02f600000000000000000000000000000000000000000000000000000000000000600000000000000000006d65726b6c65747261646510000000000000000000000000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000003b8ad8ff000000000000000000000000000000000000000000000000000000003b92790e8caf22af827a488e81a4128a029ea90f00000000000000000000000001336e58000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000"
        );
        assertEq(address(swapBridge).balance, 0);
        assertEq(usdc.balanceOf(fromUser), 0);
        assertEq(usdt.balanceOf(address(swapBridge)), 0);
        assertEq(usdc.balanceOf(address(swapBridge)), 0);
        assertEq(address(fromUser).balance, prevBalance - nativeFee); // check refund
    }

    function test_SwapAndSendToAptos_PreserveOrgBalance() public {
        swapBridge.approveMax(usdc, lzTokenBridge);
        swapBridge.approveMax(usdt, paraswapAugustusSwapper);
        (uint256 nativeFee,) = swapBridge.quoteForSend();

        address usdcRich = 0x4B16c5dE96EB2117bBE5fd171E4d203624B014aa;
        hoax(usdcRich);
        SafeERC20.safeTransfer(usdc, address(swapBridge), 1e6); // toToken org balance

        startHoax(fromUser);
        SafeERC20.safeTransfer(usdt, address(swapBridge), 2e6); // fromToken org balance
        uint256 prevBalance = address(fromUser).balance;
        SafeERC20.safeIncreaseAllowance(usdt, address(swapBridge), 1_000_000_000);
        swapBridge.swapAndSendToAptos{value: nativeFee + 100_000}(
            usdt,
            1_000_000_000, // 1000 USDT
            usdc,
            990_000_000,
            hex"01",
            hex"876a02f600000000000000000000000000000000000000000000000000000000000000600000000000000000006d65726b6c65747261646510000000000000000000000000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000003b8ad8ff000000000000000000000000000000000000000000000000000000003b92790e8caf22af827a488e81a4128a029ea90f00000000000000000000000001336e58000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000"
        );
        assertEq(address(swapBridge).balance, 0);
        assertEq(usdc.balanceOf(fromUser), 0);
        assertEq(usdt.balanceOf(address(swapBridge)), 2e6);
        assertEq(usdc.balanceOf(address(swapBridge)), 1e6);
        assertEq(address(fromUser).balance, prevBalance - nativeFee); // check refund
    }

    function test_SwapAndSendToAptos_Fail_ToAmount() public {
        swapBridge.approveMax(usdc, lzTokenBridge);
        swapBridge.approveMax(usdt, paraswapAugustusSwapper);
        (uint256 nativeFee,) = swapBridge.quoteForSend();

        startHoax(fromUser);
        SafeERC20.safeIncreaseAllowance(usdt, address(swapBridge), 1_000_000_000);
        vm.expectRevert(SwapBridge.InsufficientOutputAmount.selector);
        swapBridge.swapAndSendToAptos{value: nativeFee}(
            usdt,
            1_000_000_000, // 1000 USDT
            usdc,
            10_000_000_000,
            hex"01",
            hex"876a02f600000000000000000000000000000000000000000000000000000000000000600000000000000000006d65726b6c65747261646510000000000000000000000000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec7000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000003b9aca00000000000000000000000000000000000000000000000000000000003b8ad8ff000000000000000000000000000000000000000000000000000000003b92790e8caf22af827a488e81a4128a029ea90f00000000000000000000000001336e58000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000dac17f958d2ee523a2206206994597c13d831ec700000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000"
        );
    }

    function test_SendToAptos() public {
        swapBridge.approveMax(usdt, lzTokenBridge);
        (uint256 nativeFee,) = swapBridge.quoteForSend();

        startHoax(fromUser);
        uint256 prevBalance = address(fromUser).balance;
        SafeERC20.safeIncreaseAllowance(usdt, address(swapBridge), 1_000_000_000);
        swapBridge.sendToAptos{value: nativeFee + 100_000}(
            usdt,
            1_000_000_000, // 1000 USDT
            hex"01"
        );
        assertEq(address(swapBridge).balance, 0);
        assertEq(usdt.balanceOf(address(swapBridge)), 0);
        assertEq(address(fromUser).balance, prevBalance - nativeFee); // check refund
    }

    function test_Rescue() public {
        hoax(fromUser);
        SafeERC20.safeTransfer(usdt, address(swapBridge), 1_000_000_000);

        address recipient = makeAddr("recipient");
        hoax(deployer);
        swapBridge.rescueToken(usdt, recipient);
        assertEq(usdt.balanceOf(recipient), 1_000_000_000);
    }
}

contract SwapBridgeTest_Bsc is Test {
    IERC20 constant usdt = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IERC20 constant usdc = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);

    address constant fromUser = 0xD183F2BBF8b28d9fec8367cb06FE72B88778C86B; // some rich guy
    address constant lzTokenBridge = 0x2762409Baa1804D94D8c0bCFF8400B78Bf915D5B;
    address constant paraswapAugustusSwapper = 0x6A000F20005980200259B80c5102003040001068;

    address deployer;
    SwapBridge swapBridge;

    function setUp() public {
        uint256 mainnetForkBlock = 39836421;
        vm.createSelectFork(vm.rpcUrl("bsc"), mainnetForkBlock);

        deployer = makeAddr("deployer");
        assertEq(deployer, 0xaE0bDc4eEAC5E950B67C6819B118761CaAF61946);

        startHoax(deployer);
        swapBridge = new SwapBridge(deployer);
        assertEq(address(swapBridge), 0x8Ad159a275AEE56fb2334DBb69036E9c7baCEe9b);
        swapBridge.initialize(lzTokenBridge, paraswapAugustusSwapper);

        // fromUser
        assertGt(usdt.balanceOf(fromUser), 1000 * 1e18);
    }

    // refund toToken leftover to user when toToken decimal is greater than 6
    function test_SwapAndSendToAptos_ToToken_Leftover() public {
        swapBridge.approveMax(usdc, lzTokenBridge);
        swapBridge.approveMax(usdt, paraswapAugustusSwapper);
        (uint256 nativeFee,) = swapBridge.quoteForSend();

        startHoax(fromUser);
        uint256 fromUserUsdcOrgBalance = usdc.balanceOf(fromUser);
        SafeERC20.safeIncreaseAllowance(usdt, address(swapBridge), 1000 * 1e18);
        swapBridge.swapAndSendToAptos{value: nativeFee + 100_000}(
            usdt,
            1000 * 1e18, // 1000 USDT
            usdc,
            999 * 1e18,
            hex"01",
            hex"876a02f600000000000000000000000000000000000000000000000000000000000000600000000000000000006d65726b6c65747261646510000000000000000000000000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000055d398326f99059ff775485246999027b31979550000000000000000000000008ac76a51cc950d9822d68b83fe1ad97b32cd580d00000000000000000000000000000000000000000000003635c9adc5dea00000000000000000000000000000000000000000000000000036278ab0ffd98644c10000000000000000000000000000000000000000000000362e7a1cca30d84bf56ea52dfcfc1b43f681cd130ce54fde6b000000000000000000000000025fdb1c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000006080000000000000000000000055d398326f99059ff775485246999027b31979550000000000000000000000008ac76a51cc950d9822d68b83fe1ad97b32cd580d00000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000000"
        );
        assertEq(address(swapBridge).balance, 0);
        assertGt(usdc.balanceOf(fromUser), fromUserUsdcOrgBalance);
        assertLt(usdc.balanceOf(fromUser), fromUserUsdcOrgBalance + 1e12); // refunded leftover (less than 6 decimals)
        assertEq(usdt.balanceOf(address(swapBridge)), 0);
        assertEq(usdc.balanceOf(address(swapBridge)), 0);
    }
}
