//SPDX-Lincense-Identifier: MIT
pragma solidity ^0.8.12;

import {Test,console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;

    function setUp() public {
        // vm.startBroadcast(msg.sender);
        dsc = new DecentralizedStableCoin();
        // vm.stopBroadcast();
        // console.log("con sender", msg.sender);
    }

    ////////////////////////
    //Constructor Test ////////////////

    function testConstructor() public view {
        // console.log("Testing constructor");
        // console.log("DSC Address: ", address(dsc));
        // console.log("DSC Owner: ", dsc.owner());
        // console.log("add", address(this));
        // console.log("sender", msg.sender);
        // console.log("DSC Name: ", dsc.name());
        // console.log("DSC Symbol: ", dsc.symbol());
        // console.log("DSC Decimals: ", dsc.decimals());
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
        assertEq(dsc.decimals(), 18);
    }

    function testMustMintMoreThanZero() public {
        vm.prank(dsc.owner());
        vm.expectRevert();
        dsc.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(0);
        vm.stopPrank();
    }


    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(dsc.owner());
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(101);
        vm.stopPrank();
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(dsc.owner());
        vm.expectRevert();
        dsc.mint(address(0), 100);
        vm.stopPrank();
    }


}