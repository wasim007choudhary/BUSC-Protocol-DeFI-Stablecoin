// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {BUSC} from "../src/BUSCstablecoin.sol";
import {BUSCmotor} from "../src/BUSCmotor.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployBUSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (BUSC, BUSCmotor, HelperConfig) {
        HelperConfig hConfig = new HelperConfig();
        (
            address wethTokenAddress,
            address wbtcTokenAddress,
            address wethTokenPriceFeedAddress,
            address wbtcTokenPriceFeedAddress,
            uint256 deployerKey
        ) = hConfig.activeNetworkSettings();

        tokenAddresses = [wethTokenAddress, wbtcTokenAddress];
        priceFeedAddresses = [wethTokenPriceFeedAddress, wbtcTokenPriceFeedAddress];
        vm.startBroadcast(deployerKey);
        BUSC busc = new BUSC();
        BUSCmotor buscMotor = new BUSCmotor(tokenAddresses, priceFeedAddresses, address(busc));
        busc.transferOwnership(address(buscMotor));

        vm.stopBroadcast();
        return (busc, buscMotor, hConfig);
    }
}
