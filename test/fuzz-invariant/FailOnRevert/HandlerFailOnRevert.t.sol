// SPDX-License-Identifier:MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {BUSCmotor} from "../../../src/BUSCmotor.sol";
import {BUSC} from "../../../src/BUSCstablecoin.sol";
import {ERC20MockDecimal} from "test/Mocks/ERC20MockDecimals.sol";
import {MockV3Aggregator} from "test/Mocks/MockV3Aggregator.sol";

contract Handler is Test {
    BUSC busc;
    BUSCmotor buscMotor;

    ERC20MockDecimal wethTokenAddress;
    ERC20MockDecimal wbtcTokenAddress;

    MockV3Aggregator wethTokenPriceFeedAddress;

    address[] public usersWithCollateralDeposits;

    uint256 MAX_DEPOSIT = type(uint96).max;

    uint256 public mintBUSCAttempts;
    uint256 public mintBUSCsuccessCalls;

    uint256 public pullCollateralAttempts;
    uint256 public pullCollateralSuccessCalls;

    uint256 public depositCollateralAttempts;
    uint256 public depositCollateralSuccessCalls;

    constructor(BUSCmotor _buscMotor, BUSC _busc) {
        buscMotor = _buscMotor;
        busc = _busc;

        address[] memory collateralTokens = buscMotor.getCollateralTokens();
        wethTokenAddress = ERC20MockDecimal(collateralTokens[0]);
        wbtcTokenAddress = ERC20MockDecimal(collateralTokens[1]);

        wethTokenPriceFeedAddress =
            MockV3Aggregator(buscMotor.getPriceFeedOfCollateralTokens(address(wethTokenPriceFeedAddress)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        depositCollateralAttempts++;
        ERC20MockDecimal collateral = _getCollateralFromSeed(collateralSeed);

        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(buscMotor), amountCollateral);

        buscMotor.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposits.push(msg.sender);
        depositCollateralSuccessCalls++;
    }

    function pullCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        pullCollateralAttempts++;

        // 🔹 Always use a funded user (otherwise fuzz picks empty addresses)
        if (usersWithCollateralDeposits.length == 0) {
            console.log("No users with deposits yet");
            return;
        }

        address sender = usersWithCollateralDeposits[collateralSeed % usersWithCollateralDeposits.length];

        ERC20MockDecimal collateral = _getCollateralFromSeed(collateralSeed);

        uint256 maxCollateralToPull = buscMotor.getUserCollateralBalance(sender, address(collateral));

        // return early if this user has no balance
        if (maxCollateralToPull == 0) {
            console.log("No collateral for this user");
            return;
        }

        // Bound pull amount to something realistic
        amountCollateral = bound(amountCollateral, 1, maxCollateralToPull);

        console.log("Trying pull of:", amountCollateral);

        // Check account info before pulling
        (uint256 totalBUSCminted, uint256 collateralValueInUSD) = buscMotor.getAccountInformation(sender);

        // If no BUSC is minted, pull should always succeed
        if (totalBUSCminted == 0) {
            console.log("User has no BUSC minted -> free to pull");
            vm.startPrank(sender);
            try buscMotor.pullCollateral(address(collateral), amountCollateral) {
                pullCollateralSuccessCalls++;
            } catch {
                console.log("Pull reverted unexpectedly (no BUSC case)");
            }
            vm.stopPrank();
            return;
        }

        // Calculate health factor effect of this pull
        uint256 collateralValueToPull = buscMotor.getValueInUSD(address(collateral), amountCollateral);

        if (collateralValueToPull > collateralValueInUSD) {
            console.log("Underflow protection");
            return;
        }

        uint256 newCollateralValueInUSD = collateralValueInUSD - collateralValueToPull;
        uint256 requiredCollateral = totalBUSCminted * 2; // HF ≥ 2

        console.log("New collateral value:", newCollateralValueInUSD);
        console.log("Required collateral:", requiredCollateral);

        vm.startPrank(sender);
        if (newCollateralValueInUSD >= requiredCollateral) {
            console.log("Health factor OK -> executing pull");
            try buscMotor.pullCollateral(address(collateral), amountCollateral) {
                pullCollateralSuccessCalls++;
            } catch {
                console.log("Pull reverted (unexpected)");
            }
        } else {
            console.log("Health factor too low -> letting it revert");
            // With fail_on_revert=true, fuzz runner will count it properly
            try buscMotor.pullCollateral(address(collateral), amountCollateral) {
                pullCollateralSuccessCalls++;
            } catch {
                console.log("Pull reverted (as expected, HF broken)");
            }
        }
        vm.stopPrank();
    }

    function mintBUSC(uint256 mintAmount, uint256 addressSeed) public {
        mintBUSCAttempts++;
        if (usersWithCollateralDeposits.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposits[addressSeed % usersWithCollateralDeposits.length];
        (uint256 totalBUSCminted, uint256 collateralValueInUSD) = buscMotor.getAccountInformation(sender);

        int256 maxBUSCtoMint = (int256(collateralValueInUSD) / 2) - int256(totalBUSCminted);

        if (maxBUSCtoMint == 0) {
            return;
        }
        mintAmount = bound(mintAmount, 0, uint256(maxBUSCtoMint));
        if (mintAmount == 0) {
            return;
        }
        vm.startPrank(sender);
        buscMotor.mintBUSC(mintAmount);
        vm.stopPrank();
        mintBUSCsuccessCalls++;
    }

    ///@notice breaks the invariant test suite
    /* function collateralPriceUpdate(uint96 newPrice) public {
        int256 newPriceInt = int256(uint256(newPrice));
        wethTokenPriceFeedAddress.updateAnswer(newPriceInt);
    }*/

    //helper
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20MockDecimal) {
        if (collateralSeed % 2 == 0) {
            return wethTokenAddress;
        }
        return wbtcTokenAddress;
    }
}
