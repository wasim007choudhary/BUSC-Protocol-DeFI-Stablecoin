// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DeployBUSC} from "../../script/DeployBUSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {BUSC} from "../../src/BUSCstablecoin.sol";
import {BUSCmotor} from "../../src/BUSCmotor.sol";
import {ERC20MockDecimal} from "test/Mocks/ERC20MockDecimals.sol";
import {MockV3Aggregator} from "test/Mocks/MockV3Aggregator.sol";

contract BUSCmotorTest is StdCheats, Test {
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed tokenAmount);
    event CollateralRedeemed(
        address indexed pulledFrom, address indexed pulledTo, address indexed tokenAddress, uint256 tokenAmount
    );

    DeployBUSC deployer;
    HelperConfig hConfig;
    BUSC busc;
    BUSCmotor buscMotor;

    address wethTokenAddress;
    address wbtcTokenAddress;

    address wethTokenPriceFeedAddress;
    address wbtcTokenPriceFeedAddress;

    address public user = makeAddr("USER");
    address public liquidator = makeAddr("LIQUIDATOR");
    uint256 public constant COLLATERAL_AMOUNT_ETH = 5 ether;
    uint256 public constant COLLATERAL_AMOUNT_BTC = 5e8;
    uint256 public constant STARTING_ETH_BALANCE = 10e18;
    uint256 public constant STARTING_BTC_BALANCE = 10e8;
    uint256 public constant ETH_COLLATERAL_DEPOSITED = 2e18;
    uint256 public constant BTC_COLLATERAL_DEPOSITED = 2e8;

    function setUp() public {
        deployer = new DeployBUSC();
        (busc, buscMotor, hConfig) = deployer.run();
        (wethTokenAddress, wbtcTokenAddress, wethTokenPriceFeedAddress, wbtcTokenPriceFeedAddress,) =
            hConfig.activeNetworkSettings();
        ERC20MockDecimal(wethTokenAddress).mint(user, STARTING_ETH_BALANCE);
        ERC20MockDecimal(wbtcTokenAddress).mint(user, STARTING_BTC_BALANCE);

        delete tokenAddresses; // 🧹 Clean before each test
        delete priceFeedAddresses;
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\   Constructor Test   \/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsOnTokenAndPriceFeedLengthMismatch() public {
        tokenAddresses.push(wethTokenAddress);
        tokenAddresses.push(wbtcTokenAddress);
        priceFeedAddresses.push(wbtcTokenPriceFeedAddress);

        vm.expectRevert(
            BUSCmotor.BUSCmotor___constructor__ArrayLengthOftokenAddressAndPriceFeedAddressesMustBeSame.selector
        );
        new BUSCmotor(tokenAddresses, priceFeedAddresses, address(busc));
    }

    function testRevertsOnzeroAddressToken() public {
        tokenAddresses.push(address(0));
        tokenAddresses.push(wethTokenAddress);
        priceFeedAddresses.push(wethTokenPriceFeedAddress);
        priceFeedAddresses.push(wbtcTokenPriceFeedAddress);
        vm.expectRevert(
            BUSCmotor.BUSCmotor___constructor__ZeroAddressNotAllowedForTokenAddressesAndTokenPriceFeedAddreses.selector
        );
        new BUSCmotor(tokenAddresses, priceFeedAddresses, address(busc));
    }

    function testRevertsOnZeroAddressPriceFeed() public {
        tokenAddresses.push(wethTokenAddress);
        tokenAddresses.push(wbtcTokenAddress);
        priceFeedAddresses.push(wethTokenPriceFeedAddress);
        priceFeedAddresses.push(address(0));
        vm.expectRevert(
            BUSCmotor.BUSCmotor___constructor__ZeroAddressNotAllowedForTokenAddressesAndTokenPriceFeedAddreses.selector
        );
        new BUSCmotor(tokenAddresses, priceFeedAddresses, address(busc));
    }

    function testRevertsOnDuplicateTokenAddress() public {
        // address[] memory token = [wethTokenAddress,wethTokenAddress];
        // address[] memory priceAddress = [wethTokenPriceFeedAddress,wbtcTokenPriceFeedAddress];
        tokenAddresses.push(wethTokenAddress);
        tokenAddresses.push(wethTokenAddress);
        priceFeedAddresses.push(wethTokenPriceFeedAddress);
        priceFeedAddresses.push(wbtcTokenPriceFeedAddress);
        vm.expectRevert(BUSCmotor.BUSCmotor___constructor__CannotIncludeDuplicateTokenAddress.selector);
        new BUSCmotor(tokenAddresses, priceFeedAddresses, address(busc));
    }

    function testRevertsIfBUSCisZeroAddress() public {
        vm.expectRevert(BUSCmotor.BUSCmotor___constructor__ZeroAddressNotAllowed.selector);
        new BUSCmotor(tokenAddresses, priceFeedAddresses, address(0));
    }

    function testConstructorSetsStateCorrectly() public view {
        address expecteedAddress = address(busc);
        console.log("expecteedAddress - ", expecteedAddress);
        address actualAddress = buscMotor.getBUSCstablecoinAddress();
        console.log("actualAddress - ", actualAddress);
        assert(keccak256(abi.encodePacked(expecteedAddress)) == keccak256(abi.encodePacked(actualAddress)));
    }
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\ PriceFeed Test \/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\

    function testgetValueInUSDfunction() public view {
        //case1
        uint256 ethAmount = 5e18;
        // (4000e8 * 1e10) * 5e18 / 1e18;
        uint256 expectedETHUSDvalue = 20000e18;
        uint256 actualUSDvalue = buscMotor.getValueInUSD(wethTokenAddress, ethAmount);
        console.log("Actual Value ", actualUSDvalue);
        assert(expectedETHUSDvalue == actualUSDvalue);

        //case2
        uint256 btcAmount = 5e8;
        uint256 expectedBTCUSDvalue = 560000e18;
        uint256 actualBTCUSDvalue = buscMotor.getValueInUSD(wbtcTokenAddress, btcAmount);
        console.log("Actual Value ", actualBTCUSDvalue);
        assert(expectedBTCUSDvalue == actualBTCUSDvalue);

        //case3
        uint256 ethAmount2nd = 0.03e18;
        uint256 expected2ndEthUSDvalue = 120e18;
        uint256 actual2ndEthUSDvalue = buscMotor.getValueInUSD(wethTokenAddress, ethAmount2nd);
        console.log("Actual Value ", actual2ndEthUSDvalue);
        assertEq(expected2ndEthUSDvalue, actual2ndEthUSDvalue);

        //case4
        uint256 btcAmount2nd = 0.004e8;
        uint256 expected2ndBtcUSDvalue = 448e18;
        uint256 actual2ndWbtcUSDvalue = buscMotor.getValueInUSD(wbtcTokenAddress, btcAmount2nd);
        console.log("Actual Value ", actual2ndWbtcUSDvalue);
        assertEq(expected2ndBtcUSDvalue, actual2ndWbtcUSDvalue);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\  Deposit Collateral and GetAccountInformation \/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //for eth

    function testDepositCollateralRevertsIfAmountLessOrisZeroETH() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), COLLATERAL_AMOUNT_ETH);
        uint256 depositAmount = 0;
        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        //  vm.prank(user);
        buscMotor.depositCollateral(wethTokenAddress, depositAmount);
        vm.stopPrank();
    }

    //for btc
    function testDepositCollateralRevertsIfAmountLessOrisZeroBTC() public {
        vm.startPrank(user);
        ERC20MockDecimal(wbtcTokenAddress).approve(address(buscMotor), COLLATERAL_AMOUNT_BTC);
        uint256 depositAmount = 0;
        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        //  vm.prank(user);
        buscMotor.depositCollateral(wbtcTokenAddress, depositAmount);
        vm.stopPrank();
    }

    function testDepositCollateralRevertsOnUnallowedToken() public {
        ERC20MockDecimal anotherToken = new ERC20MockDecimal("Another", "ATK", 18, user, 20e18);
        address anotherTokenAddress = address(anotherToken);
        vm.startPrank(user);

        ERC20MockDecimal(anotherTokenAddress).approve(address(buscMotor), 4e18);
        uint256 depositAmount = 4e18;
        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_protocolAllowedToken__TokenNotAllowed.selector);
        buscMotor.depositCollateral(anotherTokenAddress, depositAmount);
        vm.stopPrank();
    }

    function testDepositColateralUpdatesStateAndEmitsEvent() public {
        uint256 depositAmount = 3e8;
        vm.startPrank(user);

        ERC20MockDecimal(wbtcTokenAddress).approve(address(buscMotor), COLLATERAL_AMOUNT_BTC);

        uint256 collateralBefore = buscMotor.getUserCollateralBalance(user, wbtcTokenAddress);
        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(user, wbtcTokenAddress, depositAmount);
        buscMotor.depositCollateral(wbtcTokenAddress, depositAmount);
        uint256 collateralAfter = buscMotor.getUserCollateralBalance(user, wbtcTokenAddress);

        assertEq(collateralBefore + depositAmount, collateralAfter);
    }

    function testDepositCollateralMultipleTimesAccumulates() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 10e18);

        uint256 initialBalance = buscMotor.getUserCollateralBalance(user, wethTokenAddress);

        buscMotor.depositCollateral(wethTokenAddress, 1e18);
        buscMotor.depositCollateral(wethTokenAddress, 2e18);

        uint256 finalBalance = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        assertEq(finalBalance, initialBalance + 3e18, "Collateral should accumulate");
        vm.stopPrank();
    }

    function testDepositCollateralWithDifferentTokens() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 1e18);
        ERC20MockDecimal(wbtcTokenAddress).approve(address(buscMotor), 1e8);

        buscMotor.depositCollateral(wethTokenAddress, 1e18);
        buscMotor.depositCollateral(wbtcTokenAddress, 1e8);

        uint256 ethBalance = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        uint256 btcBalance = buscMotor.getUserCollateralBalance(user, wbtcTokenAddress);

        assertEq(ethBalance, 1e18, "ETH collateral should be recorded");
        assertEq(btcBalance, 1e8, "BTC collateral should be recorded");
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 2e18);
        buscMotor.depositCollateral(wethTokenAddress, 2e18);
        (uint256 buscTotalminted, uint256 collateralValueInUSD) = buscMotor.getAccountInformation(user);
        uint256 expectedBUSCminted = 0;
        uint256 expectedCollateralDeposit = buscMotor.getTokenAmountFromUSDwei(wethTokenAddress, collateralValueInUSD);
        assertEq(expectedCollateralDeposit, 2e18);
        assertEq(expectedBUSCminted, buscTotalminted);
        vm.stopPrank();
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\      mintBUSC       \/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    modifier collateralDeposited() {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve((address(buscMotor)), COLLATERAL_AMOUNT_ETH);
        ERC20MockDecimal(wbtcTokenAddress).approve((address(buscMotor)), COLLATERAL_AMOUNT_BTC);
        buscMotor.depositCollateral(wethTokenAddress, ETH_COLLATERAL_DEPOSITED);
        buscMotor.depositCollateral(wbtcTokenAddress, BTC_COLLATERAL_DEPOSITED);
        vm.stopPrank();
        _;
    }

    function testmintBUSCrevertsIfAmountZero() public collateralDeposited {
        vm.startPrank(user);
        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        buscMotor.mintBUSC(0);
        vm.stopPrank();
    }

    function testMintBUSCRevertsIfNoCollateralDeposited() public {
        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                BUSCmotor.BUSCmotor___revertOnBrokenHealthFactor__BreaksTheHealthFactorThreshold.selector, 0
            )
        );
        buscMotor.mintBUSC(10 ether);
        vm.stopPrank();
    }

    function testMintBUSCWorksWithCollateral() public collateralDeposited {
        vm.startPrank(user);

        uint256 mintAmount = 10 ether;

        // Health factor before mint
        uint256 healthFactorBefore = buscMotor.getHealthFactor(user);

        // Mint BUSC
        buscMotor.mintBUSC(mintAmount);

        // Health factor after mint
        uint256 healthFactorAfter = buscMotor.getHealthFactor(user);

        // Get updated account info
        (uint256 totalBUSCminted, uint256 collateralValueInUSD) = buscMotor.getAccountInformation(user);

        // Log info for sanity check
        console.log("--------- MINT BUSC TEST ---------");
        console.log("Mint amount -> ", mintAmount);
        console.log("Total BUSC minted -> ", totalBUSCminted);
        console.log("Collateral value in USD -> ", collateralValueInUSD);
        console.log("Health factor before mint -> ", healthFactorBefore);
        console.log("Health factor after mint -> ", healthFactorAfter);

        // Assert health factor decreases
        assertGt(healthFactorBefore, healthFactorAfter);

        // Assert minted BUSC matches
        assertEq(mintAmount, totalBUSCminted);

        // Assert collateral value matches approximately (allow small rounding tolerance)
        uint256 expectedCollateralValue = buscMotor.getCollateralValueOfTheAccountInUSD(user);
        assertApproxEqAbs(collateralValueInUSD, expectedCollateralValue, 1e12); // tolerance 0.000001 ETH
    }

    function _calculateTotalCollateralUSD(address userAddress) internal view returns (uint256) {
        uint256 ethCollateral = buscMotor.getUserCollateralBalance(userAddress, wethTokenAddress);
        uint256 btcCollateral = buscMotor.getUserCollateralBalance(userAddress, wbtcTokenAddress);

        (, int256 ethPrice,,,) = MockV3Aggregator(wethTokenPriceFeedAddress).latestRoundData();
        (, int256 btcPrice,,,) = MockV3Aggregator(wbtcTokenPriceFeedAddress).latestRoundData();

        uint256 ethUSD = ((uint256(ethPrice) * 1e10) * ethCollateral) / 1e18;
        uint256 btcUSD = ((uint256(btcPrice) * 1e10) * (btcCollateral * 1e10)) / 1e18;

        console.log("ethUSD - ", ethUSD);
        console.log("btcUSD - ", btcUSD);

        return ethUSD + btcUSD;
    }

    function testMintBUSCWorksWithCollateralByMocking() public collateralDeposited {
        vm.startPrank(user);
        uint256 mintAmount = 10 ether;
        uint256 healthFactorbeforeMint = buscMotor.getHealthFactor(user);

        uint256 totalCollateralUSD = _calculateTotalCollateralUSD(user);

        console.log("totalCollateralUSD - ", totalCollateralUSD);

        (uint256 _buscMinted, uint256 collateralValueFromContractInUSD) = buscMotor.getAccountInformation(user);
        console.log("collateralValueFromContractInUSD - ", collateralValueFromContractInUSD);
        assertEq(totalCollateralUSD, collateralValueFromContractInUSD);
        assertEq(_buscMinted, 0);
        //Now Mint and check
        buscMotor.mintBUSC(mintAmount);
        uint256 healthFactorAfterMint = buscMotor.getHealthFactor(user);
        (uint256 totalBUSCminted, uint256 collateralValueFromContractInUSDafter) = buscMotor.getAccountInformation(user);
        assertEq(totalBUSCminted, mintAmount);
        assertEq(collateralValueFromContractInUSDafter, collateralValueFromContractInUSD);
        assertGt(healthFactorbeforeMint, healthFactorAfterMint);
    }

    function testMintBUSCRevertsIfHealthFactorDropsBelow1() public {
        vm.startPrank(user);
        uint256 collateralAmount = 2 ether;

        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), collateralAmount);
        buscMotor.depositCollateral(wethTokenAddress, collateralAmount);

        (, int256 price,,,) = MockV3Aggregator(wethTokenPriceFeedAddress).latestRoundData();
        uint256 buscAmountTomint = ((uint256(price) * buscMotor.getPriceFeedPrecisionFactor()) * collateralAmount)
            / buscMotor.getSolidityPrecisionFactor();

        uint256 expectedHealthFactor = buscMotor.calculateHealthFactor(
            buscAmountTomint, buscMotor.getValueInUSD(wethTokenAddress, collateralAmount)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                BUSCmotor.BUSCmotor___revertOnBrokenHealthFactor__BreaksTheHealthFactorThreshold.selector,
                expectedHealthFactor
            )
        );
        buscMotor.mintBUSC(buscAmountTomint);
        vm.stopPrank();
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\      burnBUSC       \/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    function testBurnRevertsIFbURNamountero() public collateralDeposited {
        uint256 mintBUSCamount = 5 ether;
        vm.startPrank(user);
        buscMotor.mintBUSC(mintBUSCamount);

        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        buscMotor.burnBUSC(0);
        vm.stopPrank();
    }

    function testBurnRevertsIfBurnMoreThanMinted() public collateralDeposited {
        uint256 mintBUSCamount = 5 ether;
        vm.startPrank(user);
        buscMotor.mintBUSC(mintBUSCamount);
        //vm.prank(address(buscMotor));
        busc.approve(address(buscMotor), mintBUSCamount);
        vm.expectRevert();
        buscMotor.burnBUSC(10 ether);
        vm.stopPrank();
    }

    function testBurnSuccesfullAndImporovesHealthAndUpdatesState() public collateralDeposited {
        uint256 mintBUSCamount = 5 ether;
        vm.startPrank(user);
        buscMotor.mintBUSC(mintBUSCamount);

        uint256 healthFactorBeforeBurn = buscMotor.getHealthFactor(user);
        uint256 buscAmountBeforeBurn = buscMotor.getBUSCminted(user);

        busc.approve(address(buscMotor), mintBUSCamount);
        buscMotor.burnBUSC(3 ether);

        uint256 buscAmountAfterBurn = buscMotor.getBUSCminted(user);

        uint256 healthFactorAfterBurn = buscMotor.getHealthFactor(user);

        console.log("HealthFactor Before Burn -> ", healthFactorBeforeBurn);
        console.log("HealthFactor After Burn -> ", healthFactorAfterBurn);
        console.log("BUSC amount before Burn -> ", buscAmountBeforeBurn);
        console.log("BUSC amount after burn -> ", buscAmountAfterBurn);
        assertGt(healthFactorAfterBurn, healthFactorBeforeBurn);
        assertEq(buscAmountBeforeBurn, buscAmountAfterBurn + 3 ether);
        buscMotor.burnBUSC(1 ether);
        uint256 buscAmountAfter2ndBurn = buscMotor.getBUSCminted(user);
        uint256 healthFactorAfter2ndBurn = buscMotor.getHealthFactor(user);
        assertEq(buscAmountAfterBurn, buscAmountAfter2ndBurn + 1 ether);
        assertGt(healthFactorAfter2ndBurn, healthFactorAfterBurn);
        assertGt(healthFactorAfter2ndBurn, healthFactorBeforeBurn);
        assertEq(buscAmountBeforeBurn, buscAmountAfter2ndBurn + 4 ether);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\   pullCollateral    \/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    function testPullCollateralRevertsIfAmountZero() public collateralDeposited {
        vm.startPrank(user);
        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        buscMotor.pullCollateral(wethTokenAddress, 0);
        vm.stopPrank();
    }

    function testPullCollateralRevertsIfAmountExceedsDeposited() public collateralDeposited {
        vm.startPrank(user);
        vm.expectRevert(); // through solidity ^0.8 , this will cause a subtraction underflow / revert in Solidity
        buscMotor.pullCollateral(wethTokenAddress, 4e18);
        vm.stopPrank();
    }

    function testPullCollateralRevertsIfHealthFactorBroken() public {
        uint256 depositAmount = 1 ether; //worth 4000$ i.e 4e18
        uint256 buscMintAmount = 2000e18; //mint 2000 BUSC (adjusted threshold = 50% => 2000 => health factor == 1e18 exactly)
        uint256 pullAmount = 1e17; //0.1 ether

        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve((address(buscMotor)), depositAmount);
        buscMotor.depositCollateral(wethTokenAddress, depositAmount);

        //minting up to the threshold which is allowed too by the protocol
        buscMotor.mintBUSC(buscMintAmount);

        //double-checking health factor if it is >= min
        uint256 hfBeforePull = buscMotor.getHealthFactor(user);
        uint256 minimumHF = buscMotor.getMinimumHealthFactor();

        assertGe(hfBeforePull, minimumHF);

        //trying to pull a little collateral; will break the health factor as after mint as it is to hEALTH FACTOR minimum LIMIT
        uint256 expectedHFWhenPulled = buscMotor.calculateHealthFactor(
            buscMintAmount, buscMotor.getValueInUSD(wethTokenAddress, depositAmount - pullAmount)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                BUSCmotor.BUSCmotor___revertOnBrokenHealthFactor__BreaksTheHealthFactorThreshold.selector,
                expectedHFWhenPulled
            )
        );
        buscMotor.pullCollateral(wethTokenAddress, pullAmount);

        // After revert, collateral must be unchanged and it falied to pull
        uint256 collateralAfterFailedPull = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        assertEq(collateralAfterFailedPull, depositAmount);
    }

    function testPullCollateralSucceedsAndUpdatesStateAndEmitsEvent() public {
        uint256 collateralDepositAmount = 3 ether;
        uint256 collateralWithdrawAmount = 1 ether;

        vm.startPrank(user);
        // Initial token balance of user (before deposit)
        uint256 userTokenBalanceBeforeDeposit = ERC20MockDecimal(wethTokenAddress).balanceOf(user);

        // User Token Balance Decreased after being approved first and  deposited to buscMotor
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), collateralDepositAmount);
        buscMotor.depositCollateral(wethTokenAddress, collateralDepositAmount);
        uint256 userTokenBalanceAfterDeposit = ERC20MockDecimal(wethTokenAddress).balanceOf(user);
        assertEq(userTokenBalanceAfterDeposit + collateralDepositAmount, userTokenBalanceBeforeDeposit);

        // Now the substracted Amount is stored In BUSCmotor
        uint256 userCollateralAmount = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        assertEq(userCollateralAmount, collateralDepositAmount);
        assertEq(userCollateralAmount, userTokenBalanceBeforeDeposit - userTokenBalanceAfterDeposit);

        //Event is emited when collateral pulled
        vm.expectEmit(true, true, true, false);
        emit CollateralRedeemed(user, user, wethTokenAddress, collateralWithdrawAmount);
        buscMotor.pullCollateral(wethTokenAddress, collateralWithdrawAmount);

        // state updation after Pulled
        uint256 userCollateralAfterPulled = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        assertEq(userCollateralAfterPulled, collateralDepositAmount - collateralWithdrawAmount);

        //they got thier tokens back after pulled
        uint256 userTokenBalanceAfterPullSuccess = ERC20MockDecimal(wethTokenAddress).balanceOf(user);
        assertEq(userTokenBalanceAfterPullSuccess, userTokenBalanceAfterDeposit + collateralWithdrawAmount);
    }

    function testtestPullCollateralMultipleTimesTillZeroOut() public {
        uint256 collateralDepositAmount = 4 ether;
        uint256 pullAmount = 2 ether;

        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), collateralDepositAmount);
        buscMotor.depositCollateral(wethTokenAddress, collateralDepositAmount);

        buscMotor.pullCollateral(wethTokenAddress, pullAmount);
        uint256 userBalanceAfter1stPull = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        assertEq(collateralDepositAmount - pullAmount, userBalanceAfter1stPull);

        buscMotor.pullCollateral(wethTokenAddress, pullAmount);
        uint256 userBalanceAfter2ndPull = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        assertEq(userBalanceAfter2ndPull, 0);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\       depositCollateralAndMintBUSC      \/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\//\/\/\/\/\/\/\/\/\/\\

    //function testDepositCollateralAndMintBUSC_UpdatesStateCorrectly() public {
    function testDepositCollateralAndMintBUSC_Simple() public {
        uint256 collateralDepositAmount = 2 ether;
        uint256 buscMintAmount = 5e18;
        uint256 healthFactorBeforeEverything = buscMotor.getHealthFactor(user);
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), collateralDepositAmount);
        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(user, wethTokenAddress, collateralDepositAmount);

        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, collateralDepositAmount, buscMintAmount);
        vm.stopPrank();

        assertEq(buscMotor.getUserCollateralBalance(user, wethTokenAddress), collateralDepositAmount);
        assertEq(busc.balanceOf(user), buscMintAmount);
        assertEq(buscMotor.getBUSCminted(user), buscMintAmount);
        assertTrue(buscMotor.getHealthFactor(user) >= buscMotor.getMinimumHealthFactor());
        assertGt(buscMotor.getHealthFactor(user), buscMotor.getMinimumHealthFactor());
        assertTrue(healthFactorBeforeEverything >= buscMotor.getHealthFactor(user));
        assertGt(healthFactorBeforeEverything, buscMotor.getHealthFactor(user));
    }

    function testRevertsIfMintedBUSCBreaksHealthFactor() public {
        uint256 collateralDepositAmount = 2 ether;
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), collateralDepositAmount);

        uint256 collateralVALUEinUSD = buscMotor.getValueInUSD(wethTokenAddress, collateralDepositAmount);
        uint256 maxBUSCmintable =
            (collateralVALUEinUSD * buscMotor.getLiquidationThresholdPercent()) / buscMotor.getLiuidationPrecision();

        uint256 buscAmountToMint = maxBUSCmintable + 1e18;
        uint256 expectedHealthFactor = buscMotor.calculateHealthFactor(buscAmountToMint, collateralVALUEinUSD);

        vm.expectRevert(
            abi.encodeWithSelector(
                BUSCmotor.BUSCmotor___revertOnBrokenHealthFactor__BreaksTheHealthFactorThreshold.selector,
                expectedHealthFactor
            )
        );

        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, collateralDepositAmount, buscAmountToMint);

        vm.stopPrank();
    }

    function testDepositCollateralAndMintBUSC_ZeroCollateralAmountReverts() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 10e18);
        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 0, 5e18);
    }

    function testDepositCollateralAndMintBUSC_ZeroMintAmountReverts() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 10e18);
        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 5e18, 0);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\         pullCollteralAndburnBUSC       \/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\//\/\/\/\/\/\/\/\/\/\\
    //function testpullCollateralAndBurnBUSCR_

    function testPullCollateralAndBurnBUSC_Simple() public {
        uint256 collaeralDepositAmount = 3 ether;
        uint256 buscMintAmount = 5e18;
        uint256 pullCollteralAmount = 1 ether;
        uint256 buscBurnAmount = 3e18;

        vm.startPrank(user);

        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 10e18);
        buscMotor.depositCollateral(wethTokenAddress, collaeralDepositAmount);
        buscMotor.mintBUSC(buscMintAmount);

        busc.approve(address(buscMotor), buscBurnAmount);

        vm.expectEmit(true, true, true, true);
        emit CollateralRedeemed(user, user, wethTokenAddress, pullCollteralAmount);
        buscMotor.pullCollateralAndBurnBUSC(wethTokenAddress, pullCollteralAmount, buscBurnAmount);

        assertEq(buscMotor.getBUSCminted(user), buscMintAmount - buscBurnAmount);
        assertEq(
            buscMotor.getUserCollateralBalance(user, wethTokenAddress), collaeralDepositAmount - pullCollteralAmount
        );
        assertEq(busc.balanceOf(user), buscMintAmount - buscBurnAmount);
        assertGt(buscMotor.getHealthFactor(user), buscMotor.getMinimumHealthFactor());
        assertTrue(buscMotor.getHealthFactor(user) >= buscMotor.getMinimumHealthFactor());
    }

    function testPullCollateralAndBurnBUSCRevertsOnZeroBurnAmount() public {
        vm.startPrank(user);

        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 10e18);
        buscMotor.depositCollateral(wethTokenAddress, 5e18);
        buscMotor.mintBUSC(100e18);

        busc.approve(address(buscMotor), 50e18);
        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        buscMotor.pullCollateralAndBurnBUSC(wethTokenAddress, 1e18, 0);
    }

    function testPullCollateralAndBurnBUSCRevertsOnZeroPullAmount() public {
        vm.startPrank(user);

        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 10e18);
        buscMotor.depositCollateral(wethTokenAddress, 5e18);
        buscMotor.mintBUSC(100e18);

        busc.approve(address(buscMotor), 50e18);

        vm.expectRevert(BUSCmotor.BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero.selector);
        buscMotor.pullCollateralAndBurnBUSC(wethTokenAddress, 0, 50e18);
        vm.stopPrank();
    }

    function testRevertsIfPulledCollateralBreaksHealthFactor() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve((address(buscMotor)), 1e18);
        buscMotor.depositCollateral(wethTokenAddress, 1e18);
        buscMotor.mintBUSC(2000e18);

        busc.approve(address(buscMotor), 1000e18);

        uint256 expectedHealthFactor =
            buscMotor.calculateHealthFactor(2000e18 - 1000e18, buscMotor.getValueInUSD(wethTokenAddress, 1e18 - 6e17));
        vm.expectRevert(
            abi.encodeWithSelector(
                BUSCmotor.BUSCmotor___revertOnBrokenHealthFactor__BreaksTheHealthFactorThreshold.selector,
                expectedHealthFactor
            )
        );
        buscMotor.pullCollateralAndBurnBUSC(wethTokenAddress, 6e17, 1000e18);

        uint256 collateralAfterFailedPull = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        assertEq(collateralAfterFailedPull, 1e18);

        uint256 buscBalanceAfterFailedPull = busc.balanceOf(user);
        assertEq(buscBalanceAfterFailedPull, 2000e18);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\         Liquidate       \/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\

    function testCannotLiqidateIfHealthFactorIsOK() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 1e18);
        buscMotor.depositCollateral(wethTokenAddress, 1e18);
        buscMotor.mintBUSC(2000e18);
        vm.stopPrank();

        ERC20MockDecimal(wethTokenAddress).mint(liquidator, 1e18);
        vm.startPrank(liquidator);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 1e18);
        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 1e18, 2000e18);
        busc.approve(address(buscMotor), 2000e18);
        vm.expectRevert(BUSCmotor.BUSCmotor___liquidate__NoLiquidationForThisUser_SafeHealthFactor.selector);
        buscMotor.liquidate(wethTokenAddress, user, 2000e18);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorDidNotImprove() public {
        // ---------- Arrange: USER deposits and borrows ----------
        vm.startPrank(user);

        // give USER some collateral
        ERC20MockDecimal(wethTokenAddress).mint(user, 10 ether);

        // approve and deposit + mint BUSC
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 10 ether);
        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 10 ether, 1000 ether);

        vm.stopPrank();

        // ---------- Arrange: LIQUIDATOR gets BUSC through engine ----------
        ERC20MockDecimal(wethTokenAddress).mint(liquidator, 1 ether);

        vm.startPrank(liquidator);

        // deposit collateral and mint BUSC just like USER did
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 1 ether);
        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 1 ether, 100 ether);

        vm.stopPrank();

        MockV3Aggregator(wethTokenPriceFeedAddress).updateAnswer(100e8);

        // ---------- Act + Assert ----------
        vm.startPrank(liquidator);
        busc.approve(address(buscMotor), 100e18);
        // should revert because liquidation does NOT improve health factor
        vm.expectRevert(BUSCmotor.BUSCmotor___liquidate_WellHealthFactorDidNotImprove.selector);
        buscMotor.liquidate(wethTokenAddress, user, 100 ether);

        vm.stopPrank();
    }
    // Both the tests testRevrtsIfHealthFactorNotOK and testRevertIfHealthFactorDidNotImprove pasees, so you can choose the /* */ one too now worries!

    /*
    function testRevrtsIfHealthFactorNotOK() public {
    vm.startPrank(user);
    ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor),4e18); 
    buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 4e18, 8000e18); //1 eth = 4000 dollars
    vm.stopPrank();

    MockV3Aggregator(wethTokenPriceFeedAddress).updateAnswer(500e8);

    ERC20MockDecimal(wethTokenAddress).mint(liquidator,8e18);
    
    vm.startPrank(liquidator);
    uint256 maxLiquidationAvailableInUSD = buscMotor.getValueInUSD(wethTokenAddress, 4e18); // as user deposited 4 eth which now worth 2000 dollars
    console.log("value after Price DROP", maxLiquidationAvailableInUSD);
    ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor),4e18);
    buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 4e18, 500e18); //after eth price tanks, it is 500 pereth
    busc.approve(address(buscMotor),500e18);
    vm.expectRevert(BUSCmotor.BUSCmotor___liquidate_WellHealthFactorDidNotImprove.selector);
    buscMotor.liquidate(wethTokenAddress, user,500e18 );
    vm.stopPrank(); 
    }
    */
    event Liquidation(
        address indexed liquidator,
        address indexed user,
        address indexed collateralToken,
        uint256 debtCovered,
        uint256 collateralSeized
    );

    function testLiquidationSuccessEmitsEventAndUpdatesStateAndWithdrawls() public {
        vm.startPrank(user);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 2e18);
        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 2e18, 4000e18);
        vm.stopPrank();
        MockV3Aggregator(wethTokenPriceFeedAddress).updateAnswer(3500e8);
        uint256 userHealth = buscMotor.getHealthFactor(user);

        console.log("user health factor", userHealth);
        ERC20MockDecimal(wethTokenAddress).mint(liquidator, 4e18);
        vm.startPrank(liquidator);
        ERC20MockDecimal(wethTokenAddress).approve(address(buscMotor), 4e18);
        buscMotor.depositCollateralAndMintBUSC(wethTokenAddress, 4e18, 4000e18);
        uint256 liquidatorTokenBalance = ERC20MockDecimal(wethTokenAddress).balanceOf(liquidator);
        busc.approve(address(buscMotor), 4000e18);
        uint256 collateralSeized = buscMotor.getTokenAmountFromUSDwei(wethTokenAddress, 4000e18);
        uint256 collateralSeizedWithBonus = collateralSeized + (collateralSeized * 10) / 100;
        console.log("Liquidator hf befoer liquidate", buscMotor.getHealthFactor(liquidator));
        vm.expectEmit(true, true, true, true);
        emit Liquidation(liquidator, user, wethTokenAddress, 4000e18, collateralSeizedWithBonus);
        buscMotor.liquidate(wethTokenAddress, user, 4000e18);
        vm.stopPrank();
        uint256 healtFcatorUserNow = buscMotor.getHealthFactor(user);
        uint256 liquidatorBalanceNow = ERC20MockDecimal(wethTokenAddress).balanceOf(liquidator);
        console.log("liquidatorBalanceBefore ->", liquidatorTokenBalance);
        console.log("liquidatorBalanceNow -> ", liquidatorBalanceNow);
        assertGt(healtFcatorUserNow, userHealth);
        assertGt(liquidatorBalanceNow, liquidatorTokenBalance);
        uint256 userStilHaveEth = buscMotor.getUserCollateralBalance(user, wethTokenAddress);
        assertEq(userStilHaveEth, 2e18 - collateralSeizedWithBonus);
        console.log("userStilHaveEth ->", userStilHaveEth);
        console.log("expectedUserBalance ->", uint256(2e18 - collateralSeizedWithBonus));
        console.log("User Health factor now -> ", buscMotor.getHealthFactor(user));
        console.log("Liquidator Health factor now -> ", buscMotor.getHealthFactor(liquidator));
    }
    //////////////////////////////////////////////////////////

    function testgetLiquidationBonus() public view {
        uint256 expected = 10;
        uint256 actual = buscMotor.getLiquidationBonus();
        assertEq(expected, actual);
    }

    function testgetValueInUSDraw() public {
        MockV3Aggregator(wethTokenPriceFeedAddress).updateAnswer(1000e8);

        uint256 tokenInUSD = 3000;
        uint256 expectedTokenAmount = ((tokenInUSD * 1e18) * buscMotor.getSolidityPrecisionFactor())
            / (uint256(1000e8) * buscMotor.getPriceFeedPrecisionFactor());

        uint256 actualTokenAmount = buscMotor.getTokenAmountFromRawUSD(wethTokenAddress, tokenInUSD);
        console.log("expectedTokenAmount ->", expectedTokenAmount);
        console.log("actualTokenAmount ->", actualTokenAmount);

        assertEq(expectedTokenAmount, actualTokenAmount);
    }
}
