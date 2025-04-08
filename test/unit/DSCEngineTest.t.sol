//SPDX-Lincense-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address weth;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_Collateral = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
       
    }

    ////////////////////////
    //Price Test ////////////////

    function testGetUSDValue() public view {
        uint256 ethAmount = 15e18;
        //15e18 * 2000/Eth = 30,000e18
        uint256 expectedUsdValue = 30_000e18;
        uint256 actualUsdValue = dscEngine._getUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue);
    }

  ////////////////////////
    //Deposit collateral test ////////////////
    function testRevertsIfCollateralZero() public {
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
      vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
      dscEngine.depositCollateral(weth, 0);

      vm.stopPrank();
      
    }
}
