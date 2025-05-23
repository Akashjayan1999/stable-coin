//SPDX-Lincense-Identifier: MIT
pragma solidity ^0.8.12;


import { MockV3Aggregator } from "../mocks/MocksV3Aggregator.sol";
import {Test,console} from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";



contract  OracleLibTest is StdCheats,Test {
    using OracleLib for AggregatorV3Interface;
    MockV3Aggregator public mockV3Aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITAL_PRICE = 2000 ether;

    function setUp() public {
        mockV3Aggregator = new MockV3Aggregator(
            DECIMALS,
            INITAL_PRICE
        );
    }

    function testGetTimeout() public view{
        uint256 expectedTimeout = 3 hours;
        uint256 actualTimeout = AggregatorV3Interface(address(mockV3Aggregator)).getTimeout();
        assertEq(actualTimeout, expectedTimeout);
    }
    

    function testPriceRevertsOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours + 1 seconds);
        vm.roll(block.number + 1);
         vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
          AggregatorV3Interface(address(mockV3Aggregator)).staleCheckLatestRoundData();

    }

    function testPriceRevertsOnNotUpdatedTimeStamp() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        mockV3Aggregator.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(mockV3Aggregator)).staleCheckLatestRoundData();
    }


}
