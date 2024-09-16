// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ITokenBridge} from "LayerZero-Aptos-Contract/apps/bridge-evm/contracts/interfaces/ITokenBridge.sol";
import {LzLib} from "@layerzerolabs/solidity-examples/contracts/libraries/LzLib.sol";

contract SwapBridge is Ownable2Step, Pausable {
    event SwapAndSendToAptos(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minToAmount,
        uint256 toAmount,
        bytes32 aptosAddress
    );
    event SendToAptos(address token, uint256 amount, bytes32 aptosAddress);

    error AlreadyInitialized();
    error InsufficientOutputAmount();
    error NothingToRescue();

    uint256 private constant APT_AIRDROP_AMOUNT = 9904; // signature for event collection on the Aptos side

    bool private isInit;
    ITokenBridge private tokenBridge;
    address private swapTarget;

    constructor(address _owner) Ownable(_owner) {}

    function initialize(address _tokenBridgeAddress, address _swapTarget) external onlyOwner {
        if (isInit) revert AlreadyInitialized();
        isInit = true;
        tokenBridge = ITokenBridge(_tokenBridgeAddress);
        swapTarget = _swapTarget;
    }

    function approveMax(IERC20 _token, address _spender) external whenNotPaused {
        SafeERC20.forceApprove(_token, _spender, type(uint256).max);
    }

    function _lzParams(bytes32 _aptosAddress)
        private
        view
        returns (LzLib.CallParams memory callParams, bytes memory adapterParams)
    {
        callParams = LzLib.CallParams({refundAddress: payable(msg.sender), zroPaymentAddress: address(0x0)});
        adapterParams = LzLib.buildAirdropAdapterParams(
            10000, // uaGas
            LzLib.AirdropParams({airdropAmount: APT_AIRDROP_AMOUNT, airdropAddress: _aptosAddress})
        );
    }

    function quoteForSend() external view returns (uint256 nativeFee, uint256 zroFee) {
        (LzLib.CallParams memory callParams, bytes memory adapterParams) = _lzParams(hex"01");
        (nativeFee, zroFee) = tokenBridge.quoteForSend(callParams, adapterParams);
    }

    function swapAndSendToAptos(
        IERC20 _fromToken,
        uint256 _fromAmount,
        IERC20 _toToken,
        uint256 _minToAmount,
        bytes32 _aptosAddress,
        bytes calldata _swapBytes
    ) external payable whenNotPaused {
        uint256 fromTokenOrgBalance = _fromToken.balanceOf(address(this));
        uint256 toTokenOrgBalance = _toToken.balanceOf(address(this));

        SafeERC20.safeTransferFrom(_fromToken, msg.sender, address(this), _fromAmount);

        Address.functionCall(swapTarget, _swapBytes);

        uint256 toAmount = _toToken.balanceOf(address(this)) - toTokenOrgBalance;
        if (toAmount < _minToAmount) revert InsufficientOutputAmount();

        uint256 residue = _fromToken.balanceOf(address(this)) - fromTokenOrgBalance;
        if (residue > 0) {
            SafeERC20.safeTransfer(_fromToken, msg.sender, residue);
        }

        _sendToAptos(address(_toToken), toAmount, _aptosAddress);

        if (_toToken.balanceOf(address(this)) > toTokenOrgBalance) {
            SafeERC20.safeTransfer(_toToken, msg.sender, _toToken.balanceOf(address(this)) - toTokenOrgBalance);
        }

        emit SwapAndSendToAptos(
            address(_fromToken), address(_toToken), _fromAmount, _minToAmount, toAmount, _aptosAddress
        );
    }

    function sendToAptos(IERC20 _token, uint256 _amount, bytes32 _aptosAddress) external payable whenNotPaused {
        uint256 tokenOrgBalance = _token.balanceOf(address(this));

        SafeERC20.safeTransferFrom(_token, msg.sender, address(this), _amount);

        _sendToAptos(address(_token), _amount, _aptosAddress);

        if (_token.balanceOf(address(this)) > tokenOrgBalance) {
            SafeERC20.safeTransfer(_token, msg.sender, _token.balanceOf(address(this)) - tokenOrgBalance);
        }

        emit SendToAptos(address(_token), _amount, _aptosAddress);
    }

    function _sendToAptos(address _tokenAddress, uint256 _amount, bytes32 _aptosAddress) private {
        (LzLib.CallParams memory callParams, bytes memory adapterParams) = _lzParams(_aptosAddress);
        tokenBridge.sendToAptos{value: msg.value}(_tokenAddress, _aptosAddress, _amount, callParams, adapterParams);
    }

    function rescueToken(IERC20 _token, address _recipient) external onlyOwner {
        uint256 tokenBalance = _token.balanceOf(address(this));
        if (tokenBalance == 0) revert NothingToRescue();
        SafeERC20.safeTransfer(_token, _recipient, tokenBalance);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
