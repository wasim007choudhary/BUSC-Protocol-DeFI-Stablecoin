// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {BUSC} from "src/BUSCstablecoin.sol";

contract BUSCTest is StdCheats, Test {
    BUSC busc;
    address public owner;
    address public user = makeAddr("USER");
    address public user2 = makeAddr("USER2");

    function setUp() public {
        owner = msg.sender;
        busc = new BUSC();
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\ Constructor \/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\

    function testConstructor() public view {
        string memory expectedName = "Blockchain USD Coin";
        string memory expectedSymbol = "$BUSC";

        string memory actualName = busc.name();
        string memory actualSymbol = busc.symbol();

        assert(keccak256(abi.encodePacked(actualName)) == keccak256(abi.encodePacked(expectedName)));
        assert(keccak256(abi.encodePacked(actualSymbol)) == keccak256(abi.encodePacked(expectedSymbol)));
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\     MINT    \/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    function testMintFunctionRevertsOnAmountLessOrZero() public {
        uint256 amount = 0;
        vm.expectRevert(BUSC.BUSC___mint_MintAmountMustBeAboveZero.selector);
        busc.mint(user, amount);
    }

    function testMintFunctionRevertsOnMintingToZeroAddress() public {
        uint256 amount = 10;
        vm.expectRevert(BUSC.BUSC___mint_CannotMintToInavlidOrZeroAddress.selector);
        busc.mint(address(0), amount);
    }

    function testMintFunctionRevertsIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        busc.mint(user2, 100);
    }

    function testMintFunctionSuccess() public {
        uint256 amount = 20;
        bool succes = busc.mint(user, amount);
        assertTrue(succes);
        assertEq(busc.balanceOf(user), amount);
    }

    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\     BURN    \/\/\/\/\/\/\/\/\/\/\/\\
    //\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\\
    function testBurnFunctionRevertsIfBurnAmountGreaterThanBalance() public {
        busc.mint(address(this), 100);

        vm.expectRevert(BUSC.BUSC___burn_BurnRequestExceedsAvailableBalance.selector);

        busc.burn(1001);
    }

    function testBurnFunctionRevertsOnAmountLessOrZero() public {
        busc.mint(address(this), 10);
        vm.expectRevert(BUSC.BUSC___burn_BurnAmountMustBeMoreThan_0_To_Burn.selector);
        busc.burn(0);
    }

    function testBurnFunctionRevertsIfNotOwner() public {
        busc.mint(address(this), 100);
        vm.prank(user);
        vm.expectRevert();
        busc.burn(60);
    }

    function testBurnFunctionOnValidCall() public {
        busc.mint(address(this), 20);
        busc.burn(9);
        console.log("balance -", busc.balanceOf(address(this)));
        assertEq(busc.balanceOf(address(this)), 11);
        busc.burn(11);
        console.log("balance -", busc.balanceOf(address(this)));
        assertEq(busc.balanceOf(address(this)), 0);
    }
}
