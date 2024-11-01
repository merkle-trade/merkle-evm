// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ITokenBridge} from "LayerZero-Aptos-Contract/apps/bridge-evm/contracts/interfaces/ITokenBridge.sol";
import {LzLib} from "@layerzerolabs/solidity-examples/contracts/libraries/LzLib.sol";

contract DirectDepositConfig {
    error AlreadyInitialized();
    error UnauthorizedAccount(address account);

    ITokenBridge public aptosBridge;
    IERC20 public bridgeToken;
    address public swapTarget;
    address public keeperAddress;
    address public rescueAddress;
    address public adminAddress;
    uint256 public maxFee;

    function initialize(
        ITokenBridge _aptosBridge,
        IERC20 _bridgeToken,
        address _swapTarget,
        address _keeperAddress,
        address _rescueAddress,
        address _adminAddress
    ) public {
        if (address(aptosBridge) != address(0)) revert AlreadyInitialized();
        aptosBridge = _aptosBridge;
        bridgeToken = _bridgeToken;
        swapTarget = _swapTarget;
        keeperAddress = _keeperAddress;
        rescueAddress = _rescueAddress;
        adminAddress = _adminAddress;
        maxFee = type(uint256).max;
    }

    function setMaxFee(uint256 _maxFee) external {
        if (msg.sender != adminAddress) revert UnauthorizedAccount(msg.sender);
        maxFee = _maxFee;
    }
}

contract DirectDeposit {
    event SwapAndSendToAptos(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        uint256 toAmount,
        uint256 fee,
        bytes32 aptosAddress
    );
    event SendToAptos(address token, uint256 amount, uint256 fee, bytes32 aptosAddress);

    error AlreadyInitialized();
    error UnauthorizedAccount(address account);
    error SwapError();
    error FeeTooHigh();
    error RefundFailed();
    error RescueFailed();

    DirectDepositConfig public immutable cfg;

    bytes32 public aptosAddress;

    constructor(DirectDepositConfig _cfg) {
        cfg = _cfg;
        aptosAddress = hex"01"; // prevent initialization from implementation
    }

    function initialize(bytes32 _aptosAddress) public {
        if (aptosAddress != bytes32(0)) revert AlreadyInitialized();
        aptosAddress = _aptosAddress;
    }

    function _lzParams()
        private
        view
        returns (LzLib.CallParams memory callParams, bytes memory adapterParams)
    {
        callParams = LzLib.CallParams({refundAddress: payable(msg.sender), zroPaymentAddress: address(0x0)});
        adapterParams = LzLib.buildDefaultAdapterParams(
            10000 // uaGas
        );
    }

    function quoteForSend() external view returns (uint256 nativeFee, uint256 zroFee) {
        (LzLib.CallParams memory callParams, bytes memory adapterParams) = _lzParams();
        ITokenBridge aptosBridge = cfg.aptosBridge();
        (nativeFee, zroFee) = aptosBridge.quoteForSend(callParams, adapterParams);
    }

    function swapAndSendToAptos(IERC20 _fromToken, uint256 _fromAmount, uint256 _minToAmount, uint256 _fee, bytes calldata _swapBytes)
        external
        payable
    {
        if (msg.sender != cfg.keeperAddress()) revert UnauthorizedAccount(msg.sender);

        IERC20 toToken = cfg.bridgeToken();

        uint256 nativeOrgBalance = address(this).balance;
        uint256 fromTokenOrgBalance = _fromToken.balanceOf(address(this));
        uint256 toTokenOrgBalance = toToken.balanceOf(address(this));

        // Execute the swap
        SafeERC20.forceApprove(_fromToken, cfg.swapTarget(), _fromAmount);
        Address.functionCall(cfg.swapTarget(), _swapBytes);

        // Verify the swap
        uint256 fromAmountSpent = fromTokenOrgBalance - _fromToken.balanceOf(address(this));
        if (fromAmountSpent > _fromAmount) revert SwapError();
        uint256 toAmountReceived = toToken.balanceOf(address(this)) - toTokenOrgBalance;
        if (toAmountReceived < _minToAmount) revert SwapError();

        // Deduct the fee
        if (cfg.maxFee() < _fee) revert FeeTooHigh();
        uint256 amountToSend = toAmountReceived - _fee;

        // Send to Aptos
        _sendToAptos(toToken, amountToSend, aptosAddress);

        // Send the fee
        if (_fee > 0) {
            SafeERC20.safeTransfer(toToken, msg.sender, _fee);
        }

        // Refund the native surplus
        if (address(this).balance > nativeOrgBalance) {
            (bool success,) = msg.sender.call{value: address(this).balance - nativeOrgBalance}("");
            if (!success) revert RefundFailed();
        }

        emit SwapAndSendToAptos(
            address(_fromToken), address(toToken), _fromAmount, _minToAmount, toAmountReceived, _fee, aptosAddress
        );
    }

    function sendToAptos(uint256 _amount, uint256 _fee) external payable {
        if (msg.sender != cfg.keeperAddress()) revert UnauthorizedAccount(msg.sender);

        IERC20 toToken = cfg.bridgeToken();

        uint256 nativeOrgBalance = address(this).balance;

        // Deduct the fee
        if (cfg.maxFee() < _fee) revert FeeTooHigh();
        uint256 amountToSend = _amount - _fee;

        // Send to Aptos
        _sendToAptos(toToken, amountToSend, aptosAddress);

        // Send the fee
        if (_fee > 0) {
            SafeERC20.safeTransfer(toToken, msg.sender, _fee);
        }

        // Refund the native surplus
        if (address(this).balance > nativeOrgBalance) {
            (bool success,) = msg.sender.call{value: address(this).balance - nativeOrgBalance}("");
            if (!success) revert RefundFailed();
        }

        emit SendToAptos(address(toToken), _amount, _fee, aptosAddress);
    }

    function _sendToAptos(IERC20 _token, uint256 _amount, bytes32 _aptosAddress) private {
        (LzLib.CallParams memory callParams, bytes memory adapterParams) = _lzParams();

        ITokenBridge aptosBridge = cfg.aptosBridge();
        SafeERC20.forceApprove(_token, address(aptosBridge), _amount);
        aptosBridge.sendToAptos{value: msg.value}(address(_token), _aptosAddress, _amount, callParams, adapterParams);
    }

    function rescue(IERC20 _token, address recipient) external {
        if (msg.sender != cfg.rescueAddress()) revert UnauthorizedAccount(msg.sender);

        if (address(_token) == address(0)) {
            uint256 ethBalance = address(this).balance;
            if (ethBalance == 0) revert RescueFailed();

            (bool success,) = recipient.call{value: ethBalance}("");
            if (!success) revert RescueFailed();
        } else {
            uint256 tokenBalance = _token.balanceOf(address(this));
            if (tokenBalance == 0) revert RescueFailed();

            SafeERC20.safeTransfer(_token, recipient, tokenBalance);
        }
    }
}
