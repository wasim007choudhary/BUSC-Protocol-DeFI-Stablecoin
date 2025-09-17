// SPDX-License-Identifier: MIT
// config for this test as the name suggests ->  default.invariant.fail-on-revert = false
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {BUSCmotor} from "../../../src/BUSCmotor.sol";
import {DeployBUSC} from "../../../script/DeployBUSC.s.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {BUSC} from "../../../src/BUSCstablecoin.sol";
import {ERC20MockDecimal} from "../../Mocks/ERC20MockDecimals.sol";
import {HandlerContinueOnRevert} from "./HandlerContinueOnRevert.t.sol";

contract InvariantsContinueOnRevert is StdInvariant, Test {
    BUSC public busc;
    BUSCmotor public buscMotor;
    DeployBUSC public deployer;
    HelperConfig public hConfig;
    HandlerContinueOnRevert public handler;

    address public wethTokenAddress;
    address public wbtcTokenAddress;
    address public wethTokenPriceFeedAddress;
    address public wbtcTokenPriceFeedAddress;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    address public constant USER = address(1);
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() external {
        deployer = new DeployBUSC();
        (busc, buscMotor, hConfig) = deployer.run();
        (wethTokenAddress, wbtcTokenAddress, wethTokenPriceFeedAddress, wbtcTokenPriceFeedAddress,) =
            hConfig.activeNetworkSettings();

        handler = new HandlerContinueOnRevert(busc, buscMotor);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralValueThanTotalBUSCsupplyDollars() public view {
        uint256 totalBUSCsupply = busc.totalSupply();
        uint256 totalWETHcollateralDeposited = ERC20MockDecimal(wethTokenAddress).balanceOf(address(buscMotor));
        uint256 totalWBTCcollateralDeposited = ERC20MockDecimal(wbtcTokenAddress).balanceOf(address(buscMotor));

        uint256 totalWETHvalueInUSD = buscMotor.getValueInUSD(wethTokenAddress, totalWETHcollateralDeposited);
        uint256 totalWBTCvalueInUSD = buscMotor.getValueInUSD(wbtcTokenAddress, totalWBTCcollateralDeposited);
        console.log("Total WETH value in USD -> ", totalWETHvalueInUSD);
        console.log("Total WBTC value in USD -> ", totalWBTCvalueInUSD);
        console.log("Total BUSC -> ", totalBUSCsupply);

        uint256 totalValueInUSD = totalWETHvalueInUSD + totalWBTCvalueInUSD;
        assert(totalValueInUSD >= totalBUSCsupply);
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
