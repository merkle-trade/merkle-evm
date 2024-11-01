// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ITokenBridge} from "LayerZero-Aptos-Contract/apps/bridge-evm/contracts/interfaces/ITokenBridge.sol";
import {DirectDeposit, DirectDepositConfig} from "../src/DirectDeposit.sol";
import {DirectDepositFactory} from "../src/DirectDepositFactory.sol";

abstract contract DeployScript is Script {
    bytes32 constant SALT = bytes32(bytes("MerkleTrade_241025"));

    address constant KEEPER = 0x8B1964bdd389D19e5F309ceFCB5cD5745b1A33Db;
    address constant RESCUER = 0x8B1964bdd389D19e5F309ceFCB5cD5745b1A33Db; // rescuer behind timelock
    address constant ADMIN = 0x8B1964bdd389D19e5F309ceFCB5cD5745b1A33Db;

    address constant AUGUSTUS_V6 = 0x6A000F20005980200259B80c5102003040001068;

    ITokenBridge immutable aptosBridge;
    IERC20 immutable bridgeToken;
    string network;

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl(network));
    }

    function run() public {
        vm.startBroadcast();

        address[] memory proposers = new address[](1);
        proposers[0] = RESCUER;
        address[] memory executors = new address[](1);
        executors[0] = RESCUER;
        uint256 delay = 10 days;
        TimelockController rescueTimelock = new TimelockController{salt: SALT}(delay, proposers, executors, address(0));

        proposers = new address[](1);
        proposers[0] = ADMIN;
        executors = new address[](1);
        executors[0] = ADMIN;
        delay = 1 hours;
        TimelockController adminTimelock = new TimelockController{salt: SALT}(delay, proposers, executors, address(0));

        DirectDepositConfig cfg = new DirectDepositConfig{salt: SALT}();
        cfg.initialize(aptosBridge, bridgeToken, AUGUSTUS_V6, KEEPER, address(rescueTimelock), address(adminTimelock));

        DirectDeposit impl = new DirectDeposit{salt: SALT}(cfg);

        DirectDepositFactory factory = new DirectDepositFactory{salt: SALT}(address(impl));

        vm.stopBroadcast();

        console.logAddress(address(factory));
    }
}

contract DeployScript_Sepolia is DeployScript {
    constructor() {
        aptosBridge = ITokenBridge(0x50002CdFe7CCb0C41F519c6Eb0653158d11cd907);
        bridgeToken = IERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238);
        network = "sepolia";
    }
}

contract DeployScript_Mainnet is DeployScript {
    constructor() {
        aptosBridge = ITokenBridge(0x50002CdFe7CCb0C41F519c6Eb0653158d11cd907);
        bridgeToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
        network = "mainnet";
    }
}

contract DeployScript_Bsc is DeployScript {
    constructor() {
        aptosBridge = ITokenBridge(0x2762409Baa1804D94D8c0bCFF8400B78Bf915D5B);
        bridgeToken = IERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d); // USDC
        network = "bsc";
    }
}

contract DeployScript_Polygon is DeployScript {
    constructor() {
        aptosBridge = ITokenBridge(0x488863D609F3A673875a914fBeE7508a1DE45eC6);
        bridgeToken = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // USDC.e
        network = "polygon";
    }
}

contract DeployScript_Avalanche is DeployScript {
    constructor() {
        aptosBridge = ITokenBridge(0xA5972EeE0C9B5bBb89a5B16D1d65f94c9EF25166);
        bridgeToken = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // USDC
        network = "avalanche";
    }
}

contract DeployScript_Arbitrum is DeployScript {
    constructor() {
        aptosBridge = ITokenBridge(0x1BAcC2205312534375c8d1801C27D28370656cFf);
        bridgeToken = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8); // USDC.e
        network = "arbitrum";
    }
}

contract DeployScript_Optimism is DeployScript {
    constructor() {
        aptosBridge = ITokenBridge(0x86Bb63148d17d445Ed5398ef26Aa05Bf76dD5b59);
        bridgeToken = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607); // USDC.e
        network = "optimism";
    }
}

//
// forge verify-contract \
//     --chain-id 137 \
//     --num-of-optimizations 200 \
//     --watch \
//     --constructor-args $(cast abi-encode "constructor(uint256,address[],address[],address)" 300 [0x8B1964bdd389D19e5F309ceFCB5cD5745b1A33Db] [0x8B1964bdd389D19e5F309ceFCB5cD5745b1A33Db] 0x8B1964bdd389D19e5F309ceFCB5cD5745b1A33Db) \
//     --etherscan-api-key EYSGJBXACJIRXVBJEFSQCU1CTK1JYGMVWH \
//     --compiler-version v0.8.25+commit.b61c2a91 \
//     0x9f93926C4247048E406Ae59c45113fD024d0DC99 \
//     lib/openzeppelin-contracts/contracts/governance/TimelockController.sol:TimelockController

// forge verify-contract \
//     --chain-id 137 \
//     --num-of-optimizations 200 \
//     --watch \
//     --constructor-args $(cast abi-encode "constructor()") \
//     --etherscan-api-key EYSGJBXACJIRXVBJEFSQCU1CTK1JYGMVWH \
//     --compiler-version v0.8.25+commit.b61c2a91 \
//     0x5a2a8dD5a27f6d95d6Ea49e26755d7Ad6DDF407A \
//     src/DirectDeposit.sol:DirectDepositConfig

// forge verify-contract \
//     --chain-id 137 \
//     --num-of-optimizations 200 \
//     --watch \
//     --constructor-args $(cast abi-encode "constructor(address)" 0x5a2a8dD5a27f6d95d6Ea49e26755d7Ad6DDF407A) \
//     --etherscan-api-key EYSGJBXACJIRXVBJEFSQCU1CTK1JYGMVWH \
//     --compiler-version v0.8.25+commit.b61c2a91 \
//     0xC77d9459D894DfF9be02d1b6dbb4671DF866670b \
//     src/DirectDeposit.sol:DirectDeposit

// src/DirectDeposit.sol:DirectDeposit 0xC77d9459D894DfF9be02d1b6dbb4671DF866670b

// forge verify-contract \
//     --chain-id 137 \
//     --num-of-optimizations 200 \
//     --watch \
//     --constructor-args $(cast abi-encode "constructor(address)" 0xC77d9459D894DfF9be02d1b6dbb4671DF866670b) \
//     --etherscan-api-key EYSGJBXACJIRXVBJEFSQCU1CTK1JYGMVWH \
//     --compiler-version v0.8.25+commit.b61c2a91 \
//     0x89B73D66b7BE05e43077Ef338d6f45dcc5fB328c \
//     src/DirectDepositFactory.sol:DirectDepositFactory

// src/DirectDepositFactory.sol:DirectDepositFactory 0x89B73D66b7BE05e43077Ef338d6f45dcc5fB328c
