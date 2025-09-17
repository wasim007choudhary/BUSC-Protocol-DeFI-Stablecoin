// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/Mocks/MockV3Aggregator.sol";
import {ERC20MockDecimal} from "test/Mocks/ERC20MockDecimals.sol";

contract HelperConfig is Script {
    struct NetworkConfiguration {
        address wethTokenAddress;
        address wbtcTokenAddress;
        address wethTokenPriceFeedAddress;
        address wbtcTokenPriceFeedAddress;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 4000e8;
    int256 public constant BTC_USD_PRICE = 112000e8;
    NetworkConfiguration public activeNetworkSettings;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkSettings = getSepoliaEthConfig();
        } else {
            activeNetworkSettings = createOrgetAnvilNetworkConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfiguration memory) {
        return NetworkConfiguration({
            wethTokenAddress: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtcTokenAddress: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wethTokenPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcTokenPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function createOrgetAnvilNetworkConfig() public returns (NetworkConfiguration memory) {
        if (activeNetworkSettings.wethTokenPriceFeedAddress != address(0)) {
            return activeNetworkSettings;
        }
        vm.startBroadcast();
        //for weth
        MockV3Aggregator wethPriceFeedMock = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20MockDecimal wethTokenMock = new ERC20MockDecimal("WETHmock", "WETH", 18, msg.sender, 10000e18);

        //for wbtc
        MockV3Aggregator wbtcPriceFeedMock = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20MockDecimal wbtcTokenMock = new ERC20MockDecimal("WBTCmock", "WBTC", 8, msg.sender, 9000e8);

        vm.stopBroadcast();

        return NetworkConfiguration({
            wethTokenAddress: address(wethTokenMock),
            wbtcTokenAddress: address(wbtcTokenMock),
            wethTokenPriceFeedAddress: address(wethPriceFeedMock),
            wbtcTokenPriceFeedAddress: address(wbtcPriceFeedMock),
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
        });
    }
}
