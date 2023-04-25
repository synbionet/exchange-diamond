// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {BaseTest} from "./utils/BaseTest.sol";
import {IDiamondLoupe} from "../src/diamond/interfaces/IDiamondLoupe.sol";

contract SimpleTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testCoreFacetsExist() public {
        uint256 total = IDiamondLoupe(diamondAddress).facetAddresses().length;
        assertEq(total, 4);
    }
}
