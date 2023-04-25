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

contract ExchangeFundTest is BaseTest {
    function setUp() public override {
        super.setUp();

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
    }

    function test_create_exchange() public {
        vm.startPrank(seller);
        ExchangeArgs memory args = makeDefaultInfo();
        uint256 id = ExchangeFacet(diamondAddress).createOffer(args);
        vm.stopPrank();

        Exchange memory back = BionetGettersFacet(diamondAddress).getExchange(id);
        assertEq(back.seller, seller);
        assertEq(back.buyer, buyer);
        assertEq(back.price, defaultPrice);
    }

    function test_fund_offer_expires() public {
        vm.startPrank(seller);
        ExchangeArgs memory args = makeDefaultInfo();
        uint256 id = ExchangeFacet(diamondAddress).createOffer(args);
        vm.stopPrank();

        SigUtils.Permit memory permit = makePermit(buyer, 0);
        bytes32 hashed = sigUtil.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerSecretKey, hashed);

        vm.warp(block.timestamp + 20 days);

        assertFalse(ExchangeFacet(diamondAddress).isClosed(id));

        vm.startPrank(buyer);
        ExchangeFacet(diamondAddress).fundOffer(
            id,
            ExchangePermitArgs({v: v, r: r, s: s, validFor: defaultPermitExpiration})
        );
        vm.stopPrank();

        assertTrue(ExchangeFacet(diamondAddress).isClosed(id));
    }

    function test_can_trigger_offer_expire() public {
        vm.startPrank(seller);
        ExchangeArgs memory args = makeDefaultInfo();
        uint256 id = ExchangeFacet(diamondAddress).createOffer(args);
        vm.stopPrank();

        vm.warp(block.timestamp + 20 days);

        assertFalse(ExchangeFacet(diamondAddress).isClosed(id));

        vm.startPrank(seller);
        bool r = ExchangeFacet(diamondAddress).triggerTimer(id);
        vm.stopPrank();
        assertTrue(r);

        assertTrue(ExchangeFacet(diamondAddress).isClosed(id));
    }

    function test_fund_unauthorized_caller() public {
        vm.startPrank(seller);
        ExchangeArgs memory args = makeDefaultInfo();
        uint256 id = ExchangeFacet(diamondAddress).createOffer(args);
        vm.stopPrank();

        SigUtils.Permit memory permit = makePermit(buyer, 0);
        bytes32 hashed = sigUtil.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerSecretKey, hashed);

        // Will fail as we're not pranking the buyer in the call below
        vm.expectRevert(ExchangeFacet.UnAuthorizedCaller.selector);
        ExchangeFacet(diamondAddress).fundOffer(
            id,
            ExchangePermitArgs({v: v, r: r, s: s, validFor: defaultPermitExpiration})
        );
    }

    function test_fund_insufficient_usd_funds() public {
        address brokeBuyer = vm.addr(0x11);
        vm.deal(brokeBuyer, 1 ether);

        ExchangeArgs memory args = ExchangeArgs({
            buyer: brokeBuyer,
            moderator: moderator,
            moderatorPercentage: defaultModeratorFee,
            price: defaultPrice,
            disputeTimerValue: defaultDisputeTime
        });

        vm.startPrank(seller);
        uint256 id = ExchangeFacet(diamondAddress).createOffer(args);
        vm.stopPrank();

        SigUtils.Permit memory permit = makePermit(brokeBuyer, 0);
        bytes32 hashed = sigUtil.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x11, hashed);

        vm.startPrank(brokeBuyer);
        vm.expectRevert(ExchangeFacet.InsufficientFunds.selector);
        ExchangeFacet(diamondAddress).fundOffer(
            id,
            ExchangePermitArgs({v: v, r: r, s: s, validFor: defaultPermitExpiration})
        );
        vm.stopPrank();
    }

    function test_fund_transfers_to_escrow() public {
        vm.startPrank(seller);
        ExchangeArgs memory args = makeDefaultInfo();
        uint256 id = ExchangeFacet(diamondAddress).createOffer(args);
        vm.stopPrank();

        SigUtils.Permit memory permit = makePermit(buyer, 0);
        bytes32 hashed = sigUtil.getTypedDataHash(permit);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerSecretKey, hashed);

        vm.startPrank(buyer);
        ExchangeFacet(diamondAddress).fundOffer(
            id,
            ExchangePermitArgs({v: v, r: r, s: s, validFor: defaultPermitExpiration})
        );
        vm.stopPrank();

        assertEq(usdc.balanceOf(diamondAddress), defaultPrice);
        assertEq(usdc.balanceOf(buyer), BUYER_INITIAL_BALANCE - defaultPrice);
    }
}
