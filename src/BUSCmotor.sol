// SPDX-License-Identifier: MIT

// Solidity contract Layout: - \\
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

/**
 * @notice This is the contract that will govern the contract BUSCstablecoin.sol
 * This is the motherboard/motor/core.....whatever you fill fit to say!
 */
pragma solidity ^0.8.20;

/**
 * @title BUSCmotor — 'The operator of $BUSC'
 * @author Wasim ChoudharyX
 *
 * @notice BUSCMotor is the backbone of our minimalistic, decentralized stablecoin system
 *    designed to maintain a constant 1:1 peg with the US Dollar.
 *
 * @dev This stablecoin (BUSC) exhibits the following key properties:
 * - Exogenously Collateralized
 * - Dollar-Pegged < 1:1 >
 * - Algorithmically Stabilized
 *
 * @dev Inspired by MakerDAO's DSS architecture, BUSCMotor simplifies the model by eliminating
 *   governance, fees, and complex collateral types. It supports only WETH and WBTC as backing assets.
 *
 * @dev The system is built to remain perpetually overcollateralized—at no time should the total
 * value of deposited collateral fall below the total USD-denominated value of the DSC in circulation.<-
 *
 * This contract handles all the logic for mining,redeeming BUSC, and handling collateral
 *    deposits and withdrawals.
 */

//\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
//\/\/\/\/\/\          Imports        /\/\/\/\/\/\//\\
//\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\///\\
import {BUSC} from "src/BUSCstablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OracleLib} from "./Oracle-lib/OracleLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract BUSCmotor is ReentrancyGuard {
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\          Errors         /\/\/\/\/\/\//\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\///\\
    error BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero();
    error BUSCmotor___modifier_protocolAllowedToken__TokenNotAllowed();
    error BUSCmotor___constructor__ZeroAddressNotAllowed();
    error BUSCmotor___constructor__ArrayLengthOftokenAddressAndPriceFeedAddressesMustBeSame();
    error BUSCmotor___constructor__ZeroAddressNotAllowedForTokenAddressesAndTokenPriceFeedAddreses();
    error BUSCmotor___constructor__CannotIncludeDuplicateTokenAddress();
    error BUSCmotor___depositCollateral__TransactionForCollateralDepositFailded();
    error BUSCmotor___revertOnBrokenHealthFactor__BreaksTheHealthFactorThreshold(uint256 healthFactor);
    error BUSCmotor___mintBUSC__MintingBUSCfailed();
    error BUSCmotor___pullCollateral_TransferFailed();
    error BUSCmotor___burnBUSC_BurnTransferFalied();
    error BUSCmotor___liquidate__NoLiquidationForThisUser_SafeHealthFactor();
    error BUSCmotor___liquidate_WellHealthFactorDidNotImprove();

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\           Types         /\/\/\/\/\/\//\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\///\\
    using OracleLib for AggregatorV3Interface;
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\     State Variables     /\/\/\/\/\/\//\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\///\\

    BUSC private immutable I_BUSC;

    mapping(address tokenAddress => address priceFeedAddress) private s_tokenToPriceFeed;
    mapping(address userAddress => mapping(address tokenAddress => uint256 tokenAddressAmount)) private
        s_userCollateralDeposits;
    mapping(address userAddress => uint256 buscMinted) private s_BuscAmountMintedByUser;

    address[] private s_collateralTokens;

    uint256 private constant PRICEFEED_PRECISION_FACTOR = 1e10; //as eth and btc are 1e8 in usd
    uint256 private constant SOLIDITY_PRECISION_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD_PERCENT = 50; // it means 200% overcollateralized ex for 100 eth get 50 dsc
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10 here means 10%

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\          Events         /\/\/\/\/\/\//\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\///\\
    event CollateralDeposited(address indexed user, address indexed tokenAddress, uint256 indexed tokenAmount);
    event CollateralRedeemed(
        address indexed pulledFrom, address indexed pulledTo, address indexed tokenAddress, uint256 tokenAmount
    );

    event Liquidation(
        address indexed liquidator,
        address indexed user,
        address indexed collateralToken,
        uint256 debtCovered,
        uint256 collateralSeized
    );

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\        Modifiers        /\/\/\/\/\/\//\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\///\\
    modifier greaterThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert BUSCmotor___modifier_graterThanZero__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier protocolAllowedToken(address allowedTokenAddress) {
        if (s_tokenToPriceFeed[allowedTokenAddress] == address(0)) {
            revert BUSCmotor___modifier_protocolAllowedToken__TokenNotAllowed();
        }
        _;
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/     Constructor Function      \/\/\/\/\//\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\///\\

    constructor(
        address[] memory _tokenAddresses,
        address[] memory _tokenPriceFeedAddresses,
        address buscContractAddress
    ) {
        if (_tokenAddresses.length != _tokenPriceFeedAddresses.length) {
            revert BUSCmotor___constructor__ArrayLengthOftokenAddressAndPriceFeedAddressesMustBeSame();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            if (_tokenAddresses[i] == address(0) || _tokenPriceFeedAddresses[i] == address(0)) {
                revert BUSCmotor___constructor__ZeroAddressNotAllowedForTokenAddressesAndTokenPriceFeedAddreses();
            }
            if (s_tokenToPriceFeed[_tokenAddresses[i]] != address(0)) {
                revert BUSCmotor___constructor__CannotIncludeDuplicateTokenAddress();
            }

            s_tokenToPriceFeed[_tokenAddresses[i]] = _tokenPriceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        if (buscContractAddress == address(0)) {
            revert BUSCmotor___constructor__ZeroAddressNotAllowed();
        }
        I_BUSC = BUSC(buscContractAddress);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\/\/\/\\
    //\/\/\/\/       External and Public Functions      \/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\///\/\/\/\/\/\\

    /**
     * @notice The fumction depositCollateralAndMintBUSC() is the robust version and one go version of the  depositCollateral() and mintBUSC() function
     * It takes the 2 arguements/parameters from the depositCollateral() and 1 from minTBUSC()
     *
     * @param tokenForCollateralAddress -> The address of the token about to be deposited as collateral! Check the HelperConfig.sol file for better grasping of the addresses!
     * @param collateralTokenAmount -> The amount/volume of the tokenCollateralAddress selected token to be deposited
     * @param buscAmountToMint -> Amount of BUSC to be minted after deposition!
     *
     * @notice As you can see the similarity of the 3 params of this function to depositCollateral() and mintBUSC() params!
     * That is why I said it was a kick-goal type function in one go!
     * @dev this 'depositCollateralAndMintBUSC' function will deposit your collateral and mint BEUSC in a single transaction mking it more robust and convenient for users.
     */
    function depositCollateralAndMintBUSC(
        address tokenForCollateralAddress,
        uint256 collateralTokenAmount,
        uint256 buscAmountToMint
    ) external {
        depositCollateral(tokenForCollateralAddress, collateralTokenAmount);
        mintBUSC(buscAmountToMint);
    }

    /**
     * @notice Deposits collateral into the protocol for the caller.
     * @dev
     * - Follows the CEI (Checks-Effects-Interactions) pattern:
     *   1. Checks: validates amount > 0 and token is allowed.
     *   2. Effects: updates internal accounting for user deposits.
     *   3. Interactions: pulls tokens via `transferFrom`.
     *
     * - Caller must have approved this contract to spend at least `_depositCollateralAmount`
     *   of `_collateralTokenAddress` beforehand.
     *
     * - Emits a {CollateralDeposited} event upon success.
     *
     * @param _collateralTokenAddress The ERC20 token address being deposited as collateral.
     * @param _depositCollateralAmount The amount of tokens to deposit.
     *
     * @custom:reverts BUSCmotor___depositCollateral_TransactionForCollateralDepositFailded
     * If the token transfer fails (e.g., allowance/approval missing or token non-compliant).
     */
    function depositCollateral(address _collateralTokenAddress, uint256 _depositCollateralAmount)
        public
        greaterThanZero(_depositCollateralAmount)
        protocolAllowedToken(_collateralTokenAddress)
        nonReentrant
    {
        s_userCollateralDeposits[msg.sender][_collateralTokenAddress] += _depositCollateralAmount;
        emit CollateralDeposited(msg.sender, _collateralTokenAddress, _depositCollateralAmount);
        bool success = IERC20(_collateralTokenAddress).transferFrom(msg.sender, address(this), _depositCollateralAmount);
        if (!success) {
            revert BUSCmotor___depositCollateral__TransactionForCollateralDepositFailded();
        }
    }

    /**
     * @dev It Follows the CEI method!
     *  @param _buscAmountToMint: The amount of BEUSC you want to mint
     *
     *  @notice You can only mint BEUSC if you have enough collateral than the minimum threshold!
     */
    function mintBUSC(uint256 _buscAmountToMint) public greaterThanZero(_buscAmountToMint) nonReentrant {
        _revertOnBrokenHealthFactor(msg.sender);
        s_BuscAmountMintedByUser[msg.sender] += _buscAmountToMint;
        _revertOnBrokenHealthFactor(msg.sender);
        bool mintSuccess = I_BUSC.mint(msg.sender, _buscAmountToMint);
        if (!mintSuccess) {
            revert BUSCmotor___mintBUSC__MintingBUSCfailed();
        }
    }

    /**
     * @notice The function pullCollateralAndBurnBUSC() is the robust one-go version of the burnBUSC() and pullCollateral() functions.
     * It takes 1 parameter from burnBUSC() and 2 from pu;;Collateral() to perform both operations automatically.
     *
     * @param tokenCollateralAddress -> The address of the collateral token to be pulled/claimed! Refer to HelperConfig.sol for the accepted token addresses.
     * @param amountCollateralToRedeem -> The specific amount of the collateral token to pull after burning BUSC.
     * @param buscAmountToBrun -> The amount of BUSC tokens to burn, which represents repaying your minted debt.
     * @notice This function combines BUSC burning and collateral redemption into one atomic transaction for convenience and efficiency!
     * It mirrors the structure of burnBUSC() and pullCollateral() — making it a practical, all-in-one utility function.
     *
     * @dev Useful for users who want to unwind their position in a single call: repay debt and withdraw collateral.
     * @notice Also you can see no health factor check in this function because the pullCollateral() and burnBUSC() already does that,No worries!
     */
    function pullCollateralAndBurnBUSC(
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem,
        uint256 buscAmountToBrun
    )
        external
        greaterThanZero(buscAmountToBrun)
        greaterThanZero(amountCollateralToRedeem)
        protocolAllowedToken(tokenCollateralAddress)
    {
        _burnBUSC(msg.sender, msg.sender, buscAmountToBrun);
        _pullCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateralToRedeem);
        _revertOnBrokenHealthFactor(msg.sender);
    }

    /**
     * @dev In order to claim/pull the deposited collateral, Health factor must be >1 After Collateral is claimed
     * @param collateralTokenAddress address of the collateral token to be claimed back
     *
     * @param amountCollateralToRedeem amount of the token to be claimed back!
     */
    function pullCollateral(address collateralTokenAddress, uint256 amountCollateralToRedeem)
        external
        greaterThanZero(amountCollateralToRedeem)
        nonReentrant
    {
        _pullCollateral(msg.sender, msg.sender, collateralTokenAddress, amountCollateralToRedeem);
        _revertOnBrokenHealthFactor(msg.sender);
    }

    function burnBUSC(uint256 buscAmountToBurn) external greaterThanZero(buscAmountToBurn) {
        _burnBUSC(msg.sender, msg.sender, buscAmountToBurn);
        _revertOnBrokenHealthFactor(msg.sender); // added this line for 0.00001% events it may occur out of the blue,could remove it too but that 0.00001%!
    }

    /**
     *
     * @notice Liquidates a user's undercollateralized position by burning BUSC and seizing a portion of their collateral.
     *
     * @param chooseTokenCollateralAddress The address of the ERC20 token being used as collateral for liquidation.
     * @param chooseUserToLiquidate The address of the user whose health factor has fallen below the minimum threshold (see `MINIMUM_HEALTH_FACTOR`).
     * @param debtAmountToCover The amount of BUSC the liquidator is willing to burn to help improve the target user's health factor.
     *
     * @dev This function allows for **partial liquidation**. The liquidator receives a **liquidation bonus** as an incentive for covering the debt.
     * The protocol assumes positions are **approximately 200% overcollateralized** to ensure liquidation is economically viable.
     *
     * @dev ⚠️ Known caveat: If the system falls to ~100% or lower collateralization (e.g., due to sudden price crashes), liquidations may become
     * ineffective due to insufficient collateral to reward liquidators.
     *
     * Example: If a user's collateral value drops sharply before they are liquidated, it may no longer cover their debt plus bonus.
     *
     * Follows CEI(as like the other functions in here): Checks, Effects, Interactions
     */
    function liquidate(address chooseTokenCollateralAddress, address chooseUserToLiquidate, uint256 debtAmountToCover)
        external
        greaterThanZero(debtAmountToCover)
        protocolAllowedToken(chooseTokenCollateralAddress)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(chooseUserToLiquidate);

        if (startingUserHealthFactor >= MINIMUM_HEALTH_FACTOR) {
            revert BUSCmotor___liquidate__NoLiquidationForThisUser_SafeHealthFactor();
        }

        //burn their BUSC "debt"
        //And take their collateral

        //targeted User: $150 eth, 100$ BUSC
        //debtTocover = $100 worth of BUSC
        //$100 of BUSC == ??? in eth(not in dollar, asking how much eth he will get)
        //0.05 ETH
        // also the 10% bonus from their same vault

        uint256 tokenAmountFromCoveredDebt = getTokenAmountFromUSDwei(chooseTokenCollateralAddress, debtAmountToCover);

        uint256 collteralBonusForDebtPayment = (tokenAmountFromCoveredDebt * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralAfterDebtPayment = tokenAmountFromCoveredDebt + collteralBonusForDebtPayment;
        _pullCollateral(
            chooseUserToLiquidate, msg.sender, chooseTokenCollateralAddress, totalCollateralAfterDebtPayment
        );

        _burnBUSC(chooseUserToLiquidate, msg.sender, debtAmountToCover);

        emit Liquidation(
            msg.sender,
            chooseUserToLiquidate,
            chooseTokenCollateralAddress,
            debtAmountToCover,
            totalCollateralAfterDebtPayment
        );

        uint256 endingUserHealthFactor = _healthFactor(chooseUserToLiquidate);

        // Making sure that this condtion never hits, but hey just for peace of Mint added it
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert BUSCmotor___liquidate_WellHealthFactorDidNotImprove();
        }
        _revertOnBrokenHealthFactor(msg.sender);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\           Private  Functions         /\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\

    /**
     * @dev Internal low-level function. - _pullCollateral()
     *      Should only be invoked by functions that perform the necessary health factor validations.
     */
    function _pullCollateral(
        address _from,
        address _to,
        address collateralTokenAddress,
        uint256 amountCollateralToRedeem
    ) private {
        s_userCollateralDeposits[_from][collateralTokenAddress] -= amountCollateralToRedeem;
        emit CollateralRedeemed(_from, _to, collateralTokenAddress, amountCollateralToRedeem);
        bool success = IERC20(collateralTokenAddress).transfer(_to, amountCollateralToRedeem);
        if (!success) {
            revert BUSCmotor___pullCollateral_TransferFailed();
        }
    }

    /**
     * @dev Internal low-level function.
     *      Should only be invoked by functions that perform the necessary health factor validations.
     */
    function _burnBUSC(address whoseBUSCtoBurn, address sentHereByWhomToBurn, uint256 buscAmountToBurn) private {
        s_BuscAmountMintedByUser[whoseBUSCtoBurn] -= buscAmountToBurn;
        //(buscbyWhom) means who is sending busc to this contract for burning and later burn removes it
        bool success = I_BUSC.transferFrom(sentHereByWhomToBurn, address(this), buscAmountToBurn);
        if (!success) {
            revert BUSCmotor___burnBUSC_BurnTransferFalied();
        }

        I_BUSC.burn(buscAmountToBurn);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/    Internal and Private View Functions     \/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    /**
     * @notice function _getValueInUSD() Calculates the USD value of a given token amount, accounting for token decimals.
     * @dev Internally converts all token amounts to 18 decimals to standardize calculations.
     *           Uses Chainlink price feeds to get the latest USD price of the token.
     *
     * @param tokenAddress The ERC20 token address (e.g., WETH, WBTC).
     * @param amount The amount of tokens, expressed in the token’s native decimals.
     * @return usdValue The USD value of the token amount, expressed in 18 decimals (wei-style).
     *
     * @notice @example @dev
     *
     * // Example 1: WETH (18 decimals)
     *    Price feed: 1 WETH = $4,297.24 USD (Chainlink returns 4,297.24 * 1e8)
     *    Amount: 0.5 WETH (0.5 * 1e18)
     *    Calculation:
     *              adjustTokenAmountDecimal = 0.5e18 * 10^(18-18) = 0.5e18
     *              usdValue = (4,297.24e8 * PRICEFEED_PRECISION_FACTOR) * 0.5e18 / SOLIDITY_PRECISION_FACTOR
     * //           usdValue ≈ 2,148.62e18 USD
     *
     * // Example 2: WBTC (8 decimals)
     *    Price feed: 1 WBTC = $111,645.00 USD (Chainlink returns 111,645.00 * 1e8)
     *    Amount: 0.5 WBTC (0.5 * 1e8)
     *    Calculation:
     *               adjustTokenAmountDecimal = 0.5e8 * 10^(18-8) = 0.5e18
     *               usdValue = (111,645.00e8 * PRICEFEED_PRECISION_FACTOR) * 0.5e18 / SOLIDITY_PRECISION_FACTOR
     * //            usdValue ≈ 55,822.50e18 USD
     *
     */
    function _getValueInUSD(address tokenAddress, uint256 amount) private view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[tokenAddress]);
        (, int256 price,,,) = priceFeed.stalePriceCheckLatestRoundData();

        // Get the token’s native decimals (e.g., WETH = 18, WBTC = 8)
        // lets precise it for internal calulations
        uint256 tokenDecimal = IERC20Metadata(tokenAddress).decimals();

        // Convert token amount to 18 decimals for precise internal calculation fro healthFactor and if(probably) other use cases!
        uint256 adjustTokenAmountDecimal = amount * (10 ** (18 - tokenDecimal));

        // Compute USD value in 18 decimals
        // PRICEFEED_PRECISION_FACTOR converts Chainlink 8-decimal price to 18 decimals
        // SOLIDITY_PRECISION_FACTOR keeps the final result in 18 decimals
        usdValue =
            ((uint256(price) * PRICEFEED_PRECISION_FACTOR) * adjustTokenAmountDecimal) / SOLIDITY_PRECISION_FACTOR;
        return usdValue;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalBUSCminted, uint256 collateralValueInUSD)
    {
        totalBUSCminted = s_BuscAmountMintedByUser[user];
        collateralValueInUSD = getCollateralValueOfTheAccountInUSD(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 _totalBUSCminted, uint256 _collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(_totalBUSCminted, _collateralValueInUSD);
    }

    function _calculateHealthFactor(uint256 _totalBUSCminted, uint256 _collateralValueInUSD)
        internal
        pure
        returns (uint256)
    {
        if (_totalBUSCminted == 0) {
            return type(uint256).max;
        }
        //return (_collateralValueInUSD / _totalBUSCminted);
        uint256 adjustedCollateralThreshold =
            (_collateralValueInUSD * LIQUIDATION_THRESHOLD_PERCENT) / LIQUIDATION_PRECISION;
        return (adjustedCollateralThreshold * SOLIDITY_PRECISION_FACTOR) / _totalBUSCminted;
    }

    function _revertOnBrokenHealthFactor(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MINIMUM_HEALTH_FACTOR) {
            revert BUSCmotor___revertOnBrokenHealthFactor__BreaksTheHealthFactorThreshold(userHealthFactor);
        }
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/     Public and External View Functions    \/\/\/\/\//\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\

    /**
     * @notice function getTokenAmountFromRawUSD() onverts a given USD value into the equivalent amount of a token (ETH, WBTC, etc).
     * @dev Always returns the token amount scaled to 18 decimals, regardless of the token’s native decimals.
     * @notice Better for forntEndCalls
     *
     * Workflow:
     * - Fetch the token's price in USD from Chainlink (price feeds have 8 decimals).
     * - Scale input USD to 18 decimals (so "1000" becomes "1000e18").
     * - Apply formula: (usdAmount * 1e18 * 1e18) / (price * 1e10).
     *
     * Examples:
     *
     * ETH (18 decimals):
     *  - Price feed: 1 ETH = $4000 → price = 4000e8
     *  - Input: 1000 USD → usdAmountWei = 1000e18
     *  - tokenAmount = (1000e18 * 1e18) / (4000e8 * 1e10)
     *               = 0.25e18 (0.25 ETH, 18 decimals)
     *
     * WBTC (8 decimals):
     *  - Price feed: 1 BTC = $100,000 → price = 100000e8
     *  - Input: 50,000 USD → usdAmountWei = 50000e18
     *  - tokenAmount = (50000e18 * 1e18) / (100000e8 * 1e10)
     *               = 0.5e18 (0.5 WBTC, scaled to 18 decimals)
     *
     * @param tokenAddress The address of the ERC20 token (ETH, WBTC, etc).
     * @param tokenValueInUSD The USD value (raw number, e.g., "1000" for $1000).
     * @return The equivalent token amount, scaled to 18 decimals.
     */
    function getTokenAmountFromRawUSD(address tokenAddress, uint256 tokenValueInUSD) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[tokenAddress]);
        (, int256 price,,,) = priceFeed.stalePriceCheckLatestRoundData();

        uint256 tokenValueInUSDtoWEI = tokenValueInUSD * 1e18;

        return (tokenValueInUSDtoWEI * SOLIDITY_PRECISION_FACTOR) / (uint256(price) * PRICEFEED_PRECISION_FACTOR);
    }

    /**
     * @notice In this getTokenAmountFromUSDwei() the usd value is in e18 format.
     * @dev this function expects usd value to be already in e18 format, ex, $4000 -> 4000e18
     *
     * @notice Rest of the function is same as the getTokenAmountFromUSD, only difference is e don't scale it here.
     * AS it  already expects  e18 convention in the @param tokenValueInUSDwei.
     *
     */
    function getTokenAmountFromUSDwei(address tokenAddress, uint256 tokenValueInUSDwei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[tokenAddress]);
        (, int256 price,,,) = priceFeed.stalePriceCheckLatestRoundData();

        //  uint256 tokenValueInUSDtoWEI = tokenValueInUSD * 1e18;

        return (tokenValueInUSDwei * SOLIDITY_PRECISION_FACTOR) / (uint256(price) * PRICEFEED_PRECISION_FACTOR);
    }

    function getCollateralValueOfTheAccountInUSD(address user)
        public
        view
        returns (uint256 totalCollateralValueOftheUserInUSD)
    {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenAddress = s_collateralTokens[i];
            uint256 amount = s_userCollateralDeposits[user][tokenAddress];
            totalCollateralValueOftheUserInUSD += _getValueInUSD(tokenAddress, amount);
        }
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getValueInUSD(
        address tokenAddress,
        uint256 amount // in e18
    ) external view returns (uint256) {
        return _getValueInUSD(tokenAddress, amount);
    }

    function getBUSCminted(address user) external view returns (uint256) {
        return s_BuscAmountMintedByUser[user];
    }

    function getPriceFeedPrecisionFactor() external pure returns (uint256) {
        return PRICEFEED_PRECISION_FACTOR;
    }

    function getSolidityPrecisionFactor() external pure returns (uint256) {
        return SOLIDITY_PRECISION_FACTOR;
    }

    function getLiquidationThresholdPercent() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD_PERCENT;
    }

    function getLiuidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinimumHealthFactor() external pure returns (uint256) {
        return MINIMUM_HEALTH_FACTOR;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getUserCollateralBalance(address user, address tokenAddress)
        external
        view
        returns (uint256 _tokenAmount)
    {
        return _tokenAmount = s_userCollateralDeposits[user][tokenAddress];
    }

    function getBUSCstablecoinAddress() external view returns (address) {
        return address(I_BUSC);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalBUSCminted, uint256 collateralValueInUSD)
    {
        return _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPriceFeedOfCollateralTokens(address collateralTokenAddress) external view returns (address) {
        return s_tokenToPriceFeed[collateralTokenAddress];
    }
}
