// SPDX-License-Identifier:MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BUSCmotor, AggregatorV3Interface} from "../../../src/BUSCmotor.sol";
import {BUSC} from "../../../src/BUSCstablecoin.sol";
import {ERC20MockDecimal} from "../../Mocks/ERC20MockDecimals.sol";
import {MockV3Aggregator} from "../../Mocks/MockV3Aggregator.sol";

contract HandlerContinueOnRevert is Test {
    BUSC public busc;
    BUSCmotor public buscMotor;

    ERC20MockDecimal public wethTokenAddress;
    ERC20MockDecimal public wbtcTokenAddress;

    MockV3Aggregator public wethTokenPriceFeedAddress;
    MockV3Aggregator public wbtcTokenPriceFeedAddress;

    uint256 MAX_DEPOSIT = type(uint96).max;

    // Track users with collateral to ensure some operations succeed
    address[] public usersWithCollateral;
    mapping(address => bool) public hasCollateral;

    constructor(BUSC _busc, BUSCmotor _buscMotor) {
        busc = _busc;
        buscMotor = _buscMotor;

        address[] memory collateralTokens = buscMotor.getCollateralTokens();
        wethTokenAddress = ERC20MockDecimal(collateralTokens[0]);
        wbtcTokenAddress = ERC20MockDecimal(collateralTokens[1]);

        wethTokenPriceFeedAddress =
            MockV3Aggregator(buscMotor.getPriceFeedOfCollateralTokens(address(wethTokenAddress)));
        wbtcTokenPriceFeedAddress =
            MockV3Aggregator(buscMotor.getPriceFeedOfCollateralTokens(address(wbtcTokenAddress)));

        // Bootstrap with some initial users
        _bootstrapProtocol();
    }

    function _bootstrapProtocol() private {
        // Create some initial users with collateral to ensure some operations succeed
        for (uint256 i = 0; i < 5; i++) {
            address user = address(uint160(0x1000 + i));
            usersWithCollateral.push(user);
            hasCollateral[user] = true;

            // Give them some initial collateral
            uint256 collateralAmount = 100 ether;
            wethTokenAddress.mint(user, collateralAmount);
            wbtcTokenAddress.mint(user, collateralAmount * 10 ** 10); // Account for BTC decimals

            vm.startPrank(user);
            wethTokenAddress.approve(address(buscMotor), collateralAmount);
            wbtcTokenAddress.approve(address(buscMotor), collateralAmount * 10 ** 10);

            // Deposit some collateral
            buscMotor.depositCollateral(address(wethTokenAddress), collateralAmount / 2);
            buscMotor.depositCollateral(address(wbtcTokenAddress), (collateralAmount * 10 ** 10) / 2);
            vm.stopPrank();
        }
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT);
        ERC20MockDecimal collateral = _getCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(buscMotor), amountCollateral);
        buscMotor.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        // Track users with collateral
        if (!hasCollateral[msg.sender]) {
            usersWithCollateral.push(msg.sender);
            hasCollateral[msg.sender] = true;
        }
    }

    function pullCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        // Use known users with collateral to increase success rate
        address user = _getUserWithCollateral();
        ERC20MockDecimal collateral = _getCollateralFromSeed(collateralSeed);

        uint256 userCollateral = buscMotor.getUserCollateralBalance(user, address(collateral));
        if (userCollateral == 0) return;

        amountCollateral = bound(amountCollateral, 1, userCollateral);

        vm.prank(user);
        buscMotor.pullCollateral(address(collateral), amountCollateral);
    }

    function mintBUSC(uint256 amountBUSC) public {
        // Use known users with collateral
        address user = _getUserWithCollateral();
        amountBUSC = bound(amountBUSC, 1, MAX_DEPOSIT);

        vm.prank(user);
        buscMotor.mintBUSC(amountBUSC);
    }

    function burnBUSC(uint256 amountBUSC) public {
        // Use known users who might have BUSC
        address user = _getUserWithCollateral();
        uint256 userBalance = busc.balanceOf(user);
        if (userBalance == 0) return;

        amountBUSC = bound(amountBUSC, 1, userBalance);

        vm.startPrank(user);
        busc.approve(address(buscMotor), amountBUSC);
        buscMotor.burnBUSC(amountBUSC);
        vm.stopPrank();
    }

    function liquidate(uint256 collateralSeed, uint256 debtToCover) public {
        // Try to find an undercollateralized user
        address liquidatee = _findUndercollateralizedUser();
        if (liquidatee == address(0)) return;

        ERC20MockDecimal collateral = _getCollateralFromSeed(collateralSeed);
        uint256 liquidatorBalance = busc.balanceOf(msg.sender);
        if (liquidatorBalance == 0) return;

        debtToCover = bound(debtToCover, 1, liquidatorBalance);

        vm.startPrank(msg.sender);
        busc.approve(address(buscMotor), debtToCover);
        buscMotor.liquidate(address(collateral), liquidatee, debtToCover);
        vm.stopPrank();
    }

    function transferBUSC(uint256 amountBUSC, address to) public {
        uint256 userBalance = busc.balanceOf(msg.sender);
        if (userBalance == 0) return;

        amountBUSC = bound(amountBUSC, 1, userBalance);

        vm.prank(msg.sender);
        busc.transfer(to, amountBUSC);
    }

    function updateCollateralPrice(uint256 newPrice, uint256 collateralSeed) public {
        newPrice = bound(newPrice, 1e8, 1e20);
        int256 intNewPrice = int256(newPrice);

        ERC20MockDecimal collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = MockV3Aggregator(buscMotor.getPriceFeedOfCollateralTokens(address(collateral)));

        priceFeed.updateAnswer(intNewPrice);
    }

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20MockDecimal) {
        return collateralSeed % 2 == 0 ? wethTokenAddress : wbtcTokenAddress;
    }

    function _getUserWithCollateral() private view returns (address) {
        if (usersWithCollateral.length == 0) return msg.sender;
        return usersWithCollateral[uint256(keccak256(abi.encodePacked(block.timestamp))) % usersWithCollateral.length];
    }

    function _findUndercollateralizedUser() private view returns (address) {
        for (uint256 i = 0; i < usersWithCollateral.length; i++) {
            address user = usersWithCollateral[i];
            (uint256 totalBUSC, uint256 collateralValue) = buscMotor.getAccountInformation(user);
            if (totalBUSC > 0 && collateralValue < totalBUSC * 2) {
                return user;
            }
        }
        return address(0);
    }

    function callSummary() external view {
        console.log("Weth total deposited", wethTokenAddress.balanceOf(address(buscMotor)));
        console.log("Wbtc total deposited", wbtcTokenAddress.balanceOf(address(buscMotor)));
        console.log("Total supply of BUSC", busc.totalSupply());
        console.log("Users with collateral:", usersWithCollateral.length);
    }
}
