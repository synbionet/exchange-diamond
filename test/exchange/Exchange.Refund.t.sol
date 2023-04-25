// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {SigUtils} from "../utils/SigUtils.sol";

import {
    Exchange,
    ExchangeArgs,
    ExchangePermitArgs,
    RefundType,
    RESOLVE_EXPIRES
} from "../../src/BionetTypes.sol";
import {ExchangeFacet} from "../../src/facets/ExchangeFacet.sol";
import {BionetGettersFacet} from "../../src/facets/BionetGettersFacet.sol";

import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";

contract ExchangeResolveTest is BaseTest {
    uint256 expectedProtocolPayout = 400000; // defaultPrice * 2%

    function setUp() public override {
        super.setUp();
    }

    function deployAndResolve(RefundType _rt) internal returns (uint256 eid) {}

    function test_refund_full() public {}

    function test_refund_partial() public {}

    function test_refund_none() public {}

    function test_cant_refund_timer_expired() public {}

    function test_refund_trigger_timer_expired() public {}
}
