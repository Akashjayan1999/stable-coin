// //SPDX-License-Identifier: MIT

// //Have ur invariamt aka properties

// //what are our invariants
// //1. The total supply of DSC should be less than the total value of the collateral

// //2. Getter view functions should never revert <- evergreen invariant

// pragma solidity ^0.8.12;

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant,Test {
//     DeployDSC deployer;
//     HelperConfig helperConfig;
//     DSCEngine dscEngine;
//     DecentralizedStableCoin dsc;
//     address weth;
//     address wbtc;
//    function setUp() external{
//     deployer = new DeployDSC();
//      (dsc, dscEngine, helperConfig) = deployer.run();
//      targetContract(address(dscEngine));
//       (, , weth,wbtc,) = helperConfig.activeNetworkConfig();
//    }

//    function invariant_protocalMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
//         uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));
//         uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
//         uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalBtcDeposited);
//         uint256 totalValue = wethValue + wbtcValue;
//         assert(totalValue >= totalSupply);

//    }
// }
