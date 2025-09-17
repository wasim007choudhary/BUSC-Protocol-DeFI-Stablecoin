// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployBUSC} from "../../../script/DeployBUSC.s.sol";
import {BUSCmotor} from "../../../src/BUSCmotor.sol";
import {BUSC} from "../../../src/BUSCstablecoin.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "test/Mocks/MockV3Aggregator.sol";
import {Handler} from "./HandlerFailOnRevert.t.sol";

contract InvariantsTest is StdInvariant, Test {
    BUSC busc;
    BUSCmotor buscMotor;
    DeployBUSC deployer;
    HelperConfig hConfig;
    Handler handler;
    address wethTokenAddress;
    address wbtcTokenAddress;

    function setUp() external {
        deployer = new DeployBUSC();
        (busc, buscMotor, hConfig) = deployer.run();
        (wethTokenAddress, wbtcTokenAddress,,,) = hConfig.activeNetworkSettings();
        // targetContract(address(buscMotor));
        handler = new Handler(buscMotor, busc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralthanBUSCminted() public view {
        uint256 totalBUSCsupply = busc.totalSupply();
        uint256 totalWETHcollateralDeposited = IERC20(wethTokenAddress).balanceOf(address(buscMotor));
        uint256 totalWBTCcollateralDeposited = IERC20(wbtcTokenAddress).balanceOf(address(buscMotor));

        uint256 totalWETHvalueInUSD = buscMotor.getValueInUSD(wethTokenAddress, totalWETHcollateralDeposited);
        uint256 totalWBTCvalueInUSD = buscMotor.getValueInUSD(wbtcTokenAddress, totalWBTCcollateralDeposited);
        console.log("Total WETH value in USD -> ", totalWETHvalueInUSD);
        console.log("Total WBTC value in USD -> ", totalWBTCvalueInUSD);
        console.log("Total BUSC -> ", totalBUSCsupply);

        console.log("Total Deposit Attempts -> ", handler.depositCollateralAttempts());
        console.log("Times deepositCollateral() is called -> ", handler.depositCollateralSuccessCalls());

        console.log("Total Pull Attempts -> ", handler.pullCollateralAttempts());
        console.log("Times pullCollateral() is called -> ", handler.pullCollateralSuccessCalls());

        console.log("Total Mint Attempts -> ", handler.mintBUSCAttempts());
        console.log("Times mintBUSC is called -> ", handler.mintBUSCsuccessCalls());

        uint256 totalValueInUSD = totalWETHvalueInUSD + totalWBTCvalueInUSD;
        assert(totalValueInUSD >= totalBUSCsupply);
    }

    function invariant_gettersShouldNotRevert() public {
        buscMotor.getBUSCstablecoinAddress();
        buscMotor.getLiuidationPrecision();
        buscMotor.getLiquidationThresholdPercent();
        buscMotor.getSolidityPrecisionFactor();
        buscMotor.getPriceFeedPrecisionFactor();
        buscMotor.getMinimumHealthFactor();
        buscMotor.getCollateralTokens();
    }
}
