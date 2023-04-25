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

    function deployAndFundAndDispute(ExchangeArgs memory _args)
        internal
        returns (uint256 eid)
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
        eid = ExchangeFacet(diamondAddress).createOffer(_args);
        vm.stopPrank();

        // buyer funds it
        SigUtils.Permit memory permit = makePermit(buyer, 0);
        bytes32 hashed = sigUtil.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerSecretKey, hashed);

        vm.startPrank(buyer);
        ExchangeFacet(diamondAddress).fundOffer(
            eid,
            ExchangePermitArgs({v: v, r: r, s: s, validFor: defaultPermitExpiration})
        );

        vm.warp(block.timestamp + 1 weeks);

        ExchangeFacet(diamondAddress).dispute(eid);
        vm.stopPrank();
    }

    function test_resolve_unauthorized() public {
        ExchangeArgs memory args = ExchangeArgs({
            buyer: buyer,
            moderator: moderator,
            moderatorPercentage: defaultModeratorFee,
            price: defaultPrice,
            disputeTimerValue: defaultDisputeTime
        });

        uint256 eid = deployAndFundAndDispute(args);

        // using a bad moderator
        address wrong_caller = address(0xbad);
        vm.startPrank(wrong_caller);
        vm.expectRevert(ExchangeFacet.UnAuthorizedCaller.selector);
        ExchangeFacet(diamondAddress).resolve(eid, RefundType.Full);
        vm.stopPrank();
    }

    function test_resolve_timer_expired() public {
        ExchangeArgs memory args = ExchangeArgs({
            buyer: buyer,
            moderator: moderator,
            moderatorPercentage: defaultModeratorFee,
            price: defaultPrice,
            disputeTimerValue: defaultDisputeTime
        });

        uint256 eid = deployAndFundAndDispute(args);

        vm.warp(block.timestamp + RESOLVE_EXPIRES + 1 days);

        vm.startPrank(moderator);
        vm.expectRevert(ExchangeFacet.TimerExpired.selector);
        ExchangeFacet(diamondAddress).resolve(eid, RefundType.Full);
        vm.stopPrank();
    }

    function test_resolve_seller_can_trigger() public {
        ExchangeArgs memory args = ExchangeArgs({
            buyer: buyer,
            moderator: moderator,
            moderatorPercentage: defaultModeratorFee,
            price: defaultPrice,
            disputeTimerValue: defaultDisputeTime
        });

        uint256 eid = deployAndFundAndDispute(args);

        vm.warp(block.timestamp + RESOLVE_EXPIRES + 1 days);

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
