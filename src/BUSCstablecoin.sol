// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

//imports
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol"; // can import ERC20 as Burnable is ERC20
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BUSC-StableCoin
 * @author Wasim Choudhary
 * @notice Below are the protocol it will be working on!
 *
 * Relative Stability:- pegged/anchored to USD
 * Collateral:- Exogenous (BTC & ETH) - Basically the erc20 version! wETH and wBTC
 * Minting: Algorithmic, thus decentralized
 *
 * @notice This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin
 * @notice The contract will be decreed by another contract named BUSCmotor.sol and it is the ERC20 implementation of our stablecoin system.
 */

/**
 * @dev Ownable behavior:
 * - In OZ v4.7.0, the `Ownable` constructor automatically assigns ownership
 *   to the deployer (`msg.sender`). No explicit `Ownable(msg.sender)` call is required.
 * - Starting from OZ v5.x, ownership must be explicitly set in the constructor:
 *     constructor() ERC20("TokenName", "SYM") Ownable(msg.sender) {}
 *
 * @dev For this version (v4.7.0), the default pattern is:
 *     constructor() ERC20("Blockchain USD Coin", "BUSC") {}
 */
contract BUSC is ERC20Burnable, Ownable {
    //custom errors
    error BUSC___burn_BurnRequestExceedsAvailableBalance();
    error BUSC___burn_BurnAmountMustBeMoreThan_0_To_Burn();
    error BUSC___mint_MintAmountMustBeAboveZero();
    error BUSC___mint_CannotMintToInavlidOrZeroAddress();
    // constructor

    constructor() ERC20("Blockchain USD Coin", "$BUSC") {}

    //external functions
    function mint(address _to, uint256 _mintAmount) external onlyOwner returns (bool) {
        if (_mintAmount <= 0) {
            revert BUSC___mint_MintAmountMustBeAboveZero();
        }
        if (_to == address(0)) {
            revert BUSC___mint_CannotMintToInavlidOrZeroAddress();
        }
        _mint(_to, _mintAmount);
        return true;
    }

    // public function
    function burn(uint256 _burnAmount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_burnAmount > balance) {
            revert BUSC___burn_BurnRequestExceedsAvailableBalance();
        }
        if (_burnAmount <= 0) {
            revert BUSC___burn_BurnAmountMustBeMoreThan_0_To_Burn();
        }

        super.burn(_burnAmount);
    }
}
