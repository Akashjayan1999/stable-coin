//SPDX-Lincense-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockV3Aggregator} from "../mocks/MocksV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
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
    uint256 amountToMint = 100 ether;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_Collateral = 10 ether;

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
}
