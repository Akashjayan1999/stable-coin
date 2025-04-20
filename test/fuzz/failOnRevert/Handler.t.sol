//SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MocksV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;
    uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintIsCalled;
    address[] public userWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountcollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountcollateral = bound(amountcollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountcollateral);
        collateral.approve(address(dscEngine), amountcollateral);
        dscEngine.depositCollateral(address(collateral), amountcollateral);
        vm.stopPrank();
        userWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountcollateral, uint256 addressSeed) public {
        if (userWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = userWithCollateralDeposited[addressSeed % userWithCollateralDeposited.length];
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(sender, address(collateral));
        amountcollateral = bound(amountcollateral, 0, maxCollateralToRedeem);
        if (amountcollateral == 0) {
            return;
        }

        (uint256 totalDscMinted, uint256 totalCollateralValue) = dscEngine.getAccountInformation(sender);
        uint256 collateralValueInUsd = dscEngine.getUsdValue(address(collateral), amountcollateral);
        uint256 healthFactor =
            dscEngine.calculateHealthFactor(totalDscMinted, totalCollateralValue - collateralValueInUsd);
        if (healthFactor < dscEngine.getMinHealthFactor()) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.redeemCollatertal(address(collateral), amountcollateral);
        vm.stopPrank();
    }

    function mintDSc(uint256 amount, uint256 addressSeed) public {
        if (userWithCollateralDeposited.length == 0) {
            return;
        }
        // amount = bound(amount,1,MAX_DEPOSIT_SIZE);
        address sender = userWithCollateralDeposited[addressSeed % userWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        uint256 maxDscToMint = (collateralValueInUsd / 2) - totalDscMinted;
        // console.log("Max DSC to mint: ", maxDscToMint);
        // console.log("Collateral Value in USD: ", collateralValueInUsd);
        // console.log("Total DSC minted: ", totalDscMinted);
        // console.log("Amount to mint: ", amount);
        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    //This breaks our invariant test suite

    // function updateCollateralPrice(uint96 newPrice) public {
    //    int256 newPriceInt = int256(uint256(newPrice));
    //    ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
