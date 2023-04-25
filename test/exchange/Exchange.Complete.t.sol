// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {BaseTest} from "../utils/BaseTest.sol";
import {SigUtils} from "../utils/SigUtils.sol";

import {
    Exchange, ExchangeArgs, ExchangePermitArgs
} from "../../src/BionetTypes.sol";
import {ExchangeFacet} from "../../src/facets/ExchangeFacet.sol";
import {BionetGettersFacet} from "../../src/facets/BionetGettersFacet.sol";

import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";

contract ExchangeCompleteTest is BaseTest {
    uint256 expectedProtocolPayout = 400000; // defaultPrice * 2%

    function setUp() public override {
        super.setUp();
    }

    // helper to get to the fund state.
    function deployAndSign()
        public
        returns (uint256 eid, ExchangePermitArgs memory pargs)
    {
        // Diamond deploy the facet
        ExchangeFacet ef = new ExchangeFacet();
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = (
            IDiamondCut.FacetCut({
                facetAddress: address(ef),
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: generateSelectors("ExchangeFacet")
            })
        );

        IDiamondCut(diamondAddress).diamondCut(cut, address(0x0), "");

        // Create the offer
        vm.startPrank(seller);
        ExchangeArgs memory args = makeDefaultInfo();
        eid = ExchangeFacet(diamondAddress).createOffer(args);
        vm.stopPrank();

        // buyer funds it
        SigUtils.Permit memory permit = makePermit(buyer, 0);
        bytes32 hashed = sigUtil.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerSecretKey, hashed);

        pargs =
            ExchangePermitArgs({v: v, r: r, s: s, validFor: defaultPermitExpiration});
    }

    function test_happy_path() public {
        (uint256 eid, ExchangePermitArgs memory permit) = deployAndSign();

        vm.startPrank(buyer);
        ExchangeFacet(diamondAddress).fundOffer(eid, permit);
        vm.stopPrank();

        assertEq(usdc.balanceOf(diamondAddress), defaultPrice);

        vm.startPrank(buyer);
        ExchangeFacet(diamondAddress).complete(eid);
        vm.stopPrank();

        address treasury = BionetGettersFacet(diamondAddress).getTreasuryAddress();

        assertEq(usdc.balanceOf(diamondAddress), 0);
        assertEq(usdc.balanceOf(seller), (defaultPrice - expectedProtocolPayout));
        assertEq(usdc.balanceOf(treasury), expectedProtocolPayout);
    }

    function test_must_be_right_state() public {
        (uint256 eid,) = deployAndSign();
        // We purposefully did fund the offer...
        vm.startPrank(buyer);
        vm.expectRevert(ExchangeFacet.InValidState.selector);
        ExchangeFacet(diamondAddress).complete(eid);
        vm.stopPrank();
    }

    function test_cant_trigger_until_expired() public {
        (uint256 eid,) = deployAndSign();

        // the offer is not expired ... yet
        vm.startPrank(seller);
        bool r1 = ExchangeFacet(diamondAddress).triggerTimer(eid);
        assertFalse(r1);
        vm.stopPrank();

        // now expire the offer
        vm.warp(block.timestamp + 16 days);

        vm.startPrank(seller);
        bool r2 = ExchangeFacet(diamondAddress).triggerTimer(eid);
        assertTrue(r2);
        vm.stopPrank();

        // trigging should close it.
        assertTrue(ExchangeFacet(diamondAddress).isClosed(eid));
    }

    function test_can_trigger_for_payment_when_not_completed() public {
        (uint256 eid, ExchangePermitArgs memory permit) = deployAndSign();

        vm.startPrank(buyer);
        ExchangeFacet(diamondAddress).fundOffer(eid, permit);
        vm.stopPrank();

        // advance to expire time
        vm.warp(block.timestamp + defaultDisputeTime + 1 days);

        vm.startPrank(seller);
        bool result = ExchangeFacet(diamondAddress).triggerTimer(eid);
        assertTrue(result);
        vm.stopPrank();

        address treasury = BionetGettersFacet(diamondAddress).getTreasuryAddress();

        assertEq(usdc.balanceOf(diamondAddress), 0);
        assertEq(usdc.balanceOf(seller), (defaultPrice - expectedProtocolPayout));
        assertEq(usdc.balanceOf(treasury), expectedProtocolPayout);
    }
}
