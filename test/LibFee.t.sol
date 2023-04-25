// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import {LibFee} from "../src/libraries/LibFee.sol";
import {RefundType} from "../src/BionetTypes.sol";

contract LibFeeTest is Test {
    /// Helper to bound the basispoints to the range: [0, 100]
    function boundBasisPoint(uint8 _bp) internal view returns (uint16 bp) {
        uint256 x = bound(_bp, 0, 100);
        bp = uint16(x * 100);
    }

    function test_fuzz_split(uint256 _price) public {
        (uint256 h, uint256 rem) = LibFee.split(_price);
        assertEq(_price, h + h + rem);
    }

    function test_fee_calculator() public {
        uint256 fee = LibFee.calculateFee(10e6, 200);
        assertTrue(200000 == fee);
    }

    /// Invariant: fee is always <= price
    function test_fuzz_fee_calculator(uint128 _p, uint8 _bp) public {
        uint16 basis = boundBasisPoint(_bp);
        uint256 fee = LibFee.calculateFee(_p, basis);
        assertLe(fee, _p);
    }

    /// Invariant: price == sellerFee + protocolFee
    function test_fuzz_sales_value(uint128 _price) public {
        (uint256 seller, uint256 protocol) = LibFee.payoutAndFee(_price);
        assertEq(_price, (seller + protocol));
    }

    /// Invariant: price == sellerAmt + buyerAmt + moderatorAmt + protocolRemainder
    function test_fuzz_refund(uint8 _type, uint8 _point, uint128 _price) public {
        RefundType t = RefundType.None;
        uint256 boundedType = bound(_type, 0, 2);
        if (boundedType == 1) t = RefundType.Partial;
        if (boundedType == 2) t = RefundType.Full;

        uint16 percent = boundBasisPoint(_point);

        (uint256 dS, uint256 dB, uint256 dM, uint256 dP) =
            LibFee.refund(t, percent, _price);

        assertEq(_price, (dS + dB + dM + dP));
    }
}
