//SPDX-Lincense-Identifier: MIT
pragma solidity ^0.8.12;

import {Test,console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockV3Aggregator} from "../mocks/MocksV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
contract DSCEngineTest is Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    DeployDSC deployer;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 amountToMint = 100 ether;
    address public USER = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    uint256 public constant AMOUNT_Collateral = 10 ether;
    uint256 public collateralToCover = 20 ether;
    

    event CollateralRedeemed(
        address indexed reemededFrom, address indexed reemededTo, address indexed token, uint256 amount
    );
    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,wbtc,) = helperConfig.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    ////////////////////////
    //Constructor Test ////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testREvertsIfTokenLengthIsZero() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        vm.stopPrank();
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

    function testgetTokenAmountFromUsd() public view {
        uint256 usdAmount = 30_000e18; // 30_000 ether;
        uint256 expectedEthAmount = 15e18;
        uint256 actualEthAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualEthAmount, expectedEthAmount);
    }

    ////////////////////////
    //Deposit collateral test ////////////////
    function testRevertsIfTransferFromFailsFromMainERC() public {
        MockFailedTransferFrom mockCollateralToken = new MockFailedTransferFrom();
        tokenAddresses = [address(mockCollateralToken)];
        priceFeedAddresses = [ethUsdPriceFeed];
        
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        mockCollateralToken.mint(USER, AMOUNT_Collateral);
        vm.startPrank(USER);
        
       
        ERC20Mock(address(mockCollateralToken)).approve(address(mockDscEngine), AMOUNT_Collateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.depositCollateral(address(mockCollateralToken), AMOUNT_Collateral);
        vm.stopPrank();
    }


    



    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(randToken)));
        dscEngine.depositCollateral(address(randToken), AMOUNT_Collateral);
        vm.stopPrank();
    }

    modifier depositedcollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
        dscEngine.depositCollateral(weth, AMOUNT_Collateral);
        vm.stopPrank();
        _;
    }


    function testCanDepositCollateralWithoutMinting() public depositedcollateral {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }
    function testCanDepositedCollateralAndGetAccountInfo() public depositedcollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedDepositedAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, AMOUNT_Collateral);
    }

    ///////////////////////////////////////
    // depositCollateralAndMintDsc Tests //
    ///////////////////////////////////////

     function testRevertsIfMintedDscBreaksHealthFactor() public {
          (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
          amountToMint = (uint256(price) * AMOUNT_Collateral*dscEngine.getAdditionalFeedPrecision()) / dscEngine.getPrecision();
          vm.startPrank(USER);
          ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
          uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(amountToMint,dscEngine.getUsdValue(weth, AMOUNT_Collateral));
          vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
          dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_Collateral, amountToMint);
          vm.stopPrank();
     }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
        dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_Collateral, amountToMint);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
    } 


    ///////////////////////////////////
    // mintDsc Tests //
    ///////////////////////////////////
    // This test needs it's own custom setup
    function testRevertsIfMintFails() public {
       MockFailedMintDSC mockDsc = new MockFailedMintDSC();
       tokenAddresses = [weth];
       priceFeedAddresses = [ethUsdPriceFeed];
       
       DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
       mockDsc.transferOwnership(address(mockDscEngine));
       vm.startPrank(USER);
       ERC20Mock(weth).approve(address(mockDscEngine), AMOUNT_Collateral);
       vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
       mockDscEngine.depositCollateralAndMintDSC(weth, AMOUNT_Collateral, amountToMint);
      vm.stopPrank();

    }

    function testRevertsIfMintingZero() public depositedcollateral{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDSC(0);
        vm.stopPrank();
    }

    function testRevertsIfMintAmountBreaksHealthFactor() public depositedcollateral {
       (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (AMOUNT_Collateral * (uint256(price) * dscEngine.getAdditionalFeedPrecision())) / dscEngine.getPrecision();  
        vm.startPrank(USER);
        uint256 expectedHealthFactor = dscEngine.calculateHealthFactor(amountToMint,dscEngine.getUsdValue(weth, AMOUNT_Collateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dscEngine.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedcollateral {
        vm.startPrank(USER);
        dscEngine.mintDSC(amountToMint);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amountToMint);
        vm.stopPrank();

    }

    ///////////////////////////////////
    // burnDsc Tests //
    ///////////////////////////////////

    function testRevertsIfBurnAmountIsZero() public depositedCollateralAndMintedDsc{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.burnDSC(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanUserHas() public {
        vm.prank(USER);
        vm.expectRevert();
        dscEngine.burnDSC(1);
    }


    function testCanBurnDsc() public depositedCollateralAndMintedDsc{
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.burnDSC(amountToMint);
        vm.stopPrank();
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

     ///////////////////////////////////
    // redeemCollateral Tests //
    //////////////////////////////////

    // this test needs it's own setup

    function testRevertsIfTransferFails() public {
        MockFailedTransfer mockToken = new MockFailedTransfer();
        tokenAddresses = [address(mockToken)];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        mockToken.mint(USER, AMOUNT_Collateral);
        vm.startPrank(USER);
        ERC20Mock(address(mockToken)).approve(address(mockDscEngine), AMOUNT_Collateral);
        
        mockDscEngine.depositCollateral(address(mockToken), AMOUNT_Collateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.redeemCollatertal(address(mockToken), AMOUNT_Collateral);
        vm.stopPrank();
    }

    function testRevertsIfTransferFailsasStableCoin() public {
        MockFailedTransfer mockToken = new MockFailedTransfer();
        tokenAddresses = [address(mockToken)];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockToken));
        console.log("address(this)", address(this));
        console.log("address(mockDscEngine)", address(mockDscEngine));
        
        // mockToken.transferOwnership(address(mockDscEngine));
  
        mockToken.mint(USER, AMOUNT_Collateral);
        mockToken.transferOwnership(address(mockDscEngine));
        // ERC20Mock(address(mockDscEngine)).mint(USER, AMOUNT_Collateral);
        vm.startPrank(USER);
        ERC20Mock(address(mockToken)).approve(address(mockDscEngine), AMOUNT_Collateral);
        
        mockDscEngine.depositCollateral(address(mockToken), AMOUNT_Collateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDscEngine.redeemCollatertal(address(mockToken), AMOUNT_Collateral);
        vm.stopPrank();
    }

    function testRevertsIfRedeemAmountIsZero() public depositedCollateralAndMintedDsc{
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollatertal(weth, 0);
        vm.stopPrank();

    }

    function testCanRedeemCollateral() public depositedcollateral {
        vm.startPrank(USER);
        uint256 userBalaceBeforeCollateralAmount = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalaceBeforeCollateralAmount, AMOUNT_Collateral);
        dscEngine.redeemCollatertal(weth, userBalaceBeforeCollateralAmount);
        uint256 userBalaceAfterCollateralAmount = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalaceAfterCollateralAmount, 0);
        vm.stopPrank();

    }

    function testEmitCollateralRedeemedWithCorrectArgs() public depositedcollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true, address(dscEngine));
        emit CollateralRedeemed(USER,USER, weth, AMOUNT_Collateral);
        dscEngine.redeemCollatertal(weth, AMOUNT_Collateral);
        vm.stopPrank();
    }



    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.redeemCollateralForDSC(weth, 0, amountToMint);
        vm.stopPrank();
    }

     function testCanRedeemDepositedCollateral() public depositedCollateralAndMintedDsc {
        
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), amountToMint);
        dscEngine.redeemCollateralForDSC(weth, AMOUNT_Collateral, amountToMint);
        vm.stopPrank();
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }


    ////////////////////////
    // healthFactor Tests //
    ////////////////////////
    function testProperlyReportsHealthFactor() public  depositedCollateralAndMintedDsc{
        uint256 expectedHealthFactor = 100 ether;
        uint256 healthFactor = dscEngine.getHealthFactor(USER);
        // $100 minted with $20,000 collateral at 50% liquidation threshold
        // means that we must have $200 collatareral at all times.
        // 20,000 * 0.5 = 10,000
        // 10,000 / 100 = 100 health factor
        assertEq(healthFactor, expectedHealthFactor);

        
    }

     function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        // Remember, we need $200 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
        // 180*50 (LIQUIDATION_THRESHOLD) / 100 (LIQUIDATION_PRECISION) / 100 (PRECISION) = 90 / 100 (totalDscMinted) =
        // 0.9
        assert(userHealthFactor == 0.9 ether);
    }

     ///////////////////////
    // Liquidation Tests //
    ///////////////////////
    // This test needs it's own setup
   function testMustImproveHealthFactorOnLiquidation() public {
      MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
      tokenAddresses = [weth];
      priceFeedAddresses = [ethUsdPriceFeed];
      DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
      mockDsc.transferOwnership(address(mockDsce));
     // Arrange - User
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(mockDsce), AMOUNT_Collateral);
      mockDsce.depositCollateralAndMintDSC(weth, AMOUNT_Collateral, amountToMint);
      vm.stopPrank();
     // Arrange - Liquidator
      collateralToCover = 1 ether;
      ERC20Mock(weth).mint(liquidator, collateralToCover);

      vm.startPrank(liquidator);
      ERC20Mock(weth).approve(address(mockDsce), collateralToCover);
      uint256 debtToCover = 10 ether;
      mockDsce.depositCollateralAndMintDSC(weth, collateralToCover, amountToMint);
      mockDsc.approve(address(mockDsce), debtToCover);

         // Act
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

         // Act/Assert
        vm.expectRevert(DSCEngine.DSCEngine__HealthFatorNotImproved.selector);
        mockDsce.liquidate(weth, USER, debtToCover);
        vm.stopPrank();
      
   }

   function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc{
       ERC20Mock(weth).mint(liquidator, collateralToCover);
       vm.startPrank(liquidator);
       ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
       dscEngine.depositCollateralAndMintDSC(weth, collateralToCover, amountToMint);
       dsc.approve(address(dscEngine), amountToMint);

       vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
       dscEngine.liquidate(weth, USER, amountToMint);
       vm.stopPrank();
   }


   modifier liquidated() {
      vm.startPrank(USER);
      ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
      dscEngine.depositCollateralAndMintDSC(weth, AMOUNT_Collateral, amountToMint);
      vm.stopPrank();

      int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
      MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
      uint256 userHealthFactor = dscEngine.getHealthFactor(USER);
      ERC20Mock(weth).mint(liquidator, collateralToCover);

      vm.startPrank(liquidator);
      ERC20Mock(weth).approve(address(dscEngine), collateralToCover);
      dscEngine.depositCollateralAndMintDSC(weth, collateralToCover, amountToMint);
      dsc.approve(address(dscEngine), amountToMint);

      dscEngine.liquidate(weth, USER, amountToMint);// We are covering their whole debt
      vm.stopPrank();
    


      _;
   }

   function testLiquidationPayoutIsCorrect() public liquidated {
     uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
     uint256 expectedWeth = dscEngine.getTokenAmountFromUsd(weth, amountToMint)
            + (dscEngine.getTokenAmountFromUsd(weth, amountToMint) * dscEngine.getLiquidationBonus() / dscEngine.getLiquidationPrecision());
        uint256 hardCodedExpected = 6_111_111_111_111_111_110;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);

   }


    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated  = dscEngine.getTokenAmountFromUsd(weth, amountToMint)
            + (dscEngine.getTokenAmountFromUsd(weth, amountToMint) * dscEngine.getLiquidationBonus() / dscEngine.getLiquidationPrecision());

        uint256 usdAmountLiquidated = dscEngine.getUsdValue(weth, amountLiquidated);
         uint256 expectedUserCollateralValueInUsd = dscEngine.getUsdValue(weth, AMOUNT_Collateral) - (usdAmountLiquidated);
          (, uint256 userCollateralValueInUsd) = dscEngine.getAccountInformation(USER);
          uint256 hardCodedExpectedValue = 70_000_000_000_000_000_020;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

     function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dscEngine.getAccountInformation(liquidator);
        assertEq(liquidatorDscMinted, amountToMint);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }







   ///////////////////////////////////
    // View & Pure Function Tests //
    ////////////////////////////////// 
    function testGetCollateralTokenPriceFeed() public view{
        address priceFeed = dscEngine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

     function testGetCollateralTokens() public view{
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }


    function testGetMinHealthFactor() public view{
        uint256 minHealthFactor = dscEngine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR );
    }

     function testGetLiquidationThreshold() public view{
        uint256 liquidationThreshold = dscEngine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }




    function testGetAccountCollateralValueFromInformation() public depositedcollateral{
        (, uint256 collateralValue) = dscEngine.getAccountInformation(USER);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(weth, AMOUNT_Collateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
        dscEngine.depositCollateral(weth, AMOUNT_Collateral);
        vm.stopPrank();
        uint256 collateralBalance = dscEngine.getCollateralBalanceOfUser(USER, weth);
        assertEq(collateralBalance, AMOUNT_Collateral);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_Collateral);
        dscEngine.depositCollateral(weth, AMOUNT_Collateral);
        vm.stopPrank();
        uint256 collateralValue = dscEngine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = dscEngine.getUsdValue(weth, AMOUNT_Collateral);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDsc() public view{
        address dscAddress = dscEngine.getDsc();
        assertEq(dscAddress, address(dsc));
    }

    function testLiquidationPrecision() public view{
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dscEngine.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
    
}

