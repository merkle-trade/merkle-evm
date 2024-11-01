// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {LibClone} from "solady/utils/LibClone.sol";
import {DirectDeposit} from "./DirectDeposit.sol";

contract DirectDepositFactory {
    event DirectDepositDeployed(address indexed deployedAddress, bytes32 indexed aptosAddress, uint256 nonce);

    error InvalidAddress();

    address public immutable implementation;

    constructor(address _implementation) payable {
        implementation = _implementation;
    }

    function deploy(bytes32 _aptosAddress, uint256 _nonce) public returns (DirectDeposit) {
        if (_aptosAddress == bytes32(0)) revert InvalidAddress();

        (bool alreadyDeployed, address deployAddress) =
            LibClone.createDeterministicERC1967(implementation, _getSalt(_aptosAddress, _nonce));

        address predictedAddress = getAddress(_aptosAddress, _nonce);
        if (deployAddress != predictedAddress) revert InvalidAddress(); // sanity check; should never happen

        DirectDeposit directDeposit = DirectDeposit(payable(deployAddress));
        if (!alreadyDeployed) {
            directDeposit.initialize(_aptosAddress);
            emit DirectDepositDeployed(address(directDeposit), _aptosAddress, _nonce);
        }
        return directDeposit;
    }

    function getAddress(bytes32 _aptosAddress, uint256 _nonce) public view returns (address) {
        bytes32 initCodeHash = LibClone.initCodeHashERC1967(implementation);
        return LibClone.predictDeterministicAddress(initCodeHash, _getSalt(_aptosAddress, _nonce), address(this));
    }

    function _getSalt(bytes32 _aptosAddress, uint256 _nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(_aptosAddress, _nonce));
    }
}
