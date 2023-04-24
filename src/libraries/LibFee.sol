// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {RefundType} from "../BionetTypes.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @dev Library to calculate sale values and fees
library LibFee {
    uint16 constant DEFAULT_PROTOCOL_BASIS = 200;

    /// reverts is basis points are > 10_000
    error InvalidBasisPoint();

    /// @dev Divide a value in half.  Integer division will round down. So return
    /// the half and any remainder.
    /// @param _price to divide
    /// @return half and the remainder
    function split(uint256 _price)
        internal
        pure
        returns (uint256 half, uint256 rem)
    {
        if (_price == 0) return (0, 0);
        rem = _price % 2;
        half = _price / 2;
    }

    /// @notice Calculate the fee as a percentage of the price.  Basis points are
    /// used to calculate percentages.  For example 1% = 100 (1* 100) basis points,
    /// and 100% = 10_000 (100 * 100).
    ///
    /// Will revert if
    ///  - basis is > 10_000
    ///  - price * basis overflows or underflows
    ///
    /// @param _price to calculate against. Notice it's a u128 to prevent
    /// under/overflows
    /// @param _basis point.
    /// @return fee
    function calculateFee(uint256 _price, uint16 _basis)
        internal
        pure
        returns (uint256 fee)
    {
        if (_price == 0 || _basis == 0) return 0;
        if (_basis > 10_000) revert InvalidBasisPoint();
        fee = FixedPointMathLib.mulDivDown(_price, _basis, 10_000);
    }

    /// @dev Calculate the payout to seller and the protocol fee.
    /// Current the protocol % fee is fixed at 2%. TODO: make configurable
    /// @param _price of the item
    /// @return seller amount protocol fee amount
    function payoutAndFee(uint256 _price)
        internal
        pure
        returns (uint256 seller, uint256 fee)
    {
        fee = calculateFee(_price, DEFAULT_PROTOCOL_BASIS);
        seller = _price - fee;
    }

    /// @dev Calculate the amount of refund and the payout (if any) to all parties.
    /// Note: the protocol only receives an amount if a 50% refunds leaves a very
    /// small remainder.
    /// @param _type of Refund selected by the moderator
    /// @param _moderatorBasisPoints is the moderator percentage rate
    /// @param _price of the item
    /// @return seller amount, buyer amount, moderator amount, and any remainder to
    /// the protocol.
    function refund(RefundType _type, uint16 _moderatorBasisPoints, uint256 _price)
        internal
        pure
        returns (uint256 seller, uint256 buyer, uint256 moderator, uint256 protocol)
    {
        // moderator always gets paid
        moderator = calculateFee(_price, _moderatorBasisPoints);
        // divide this up
        uint256 balance = _price - moderator;

        if (_type == RefundType.None) {
            // pay seller less moderator fee
            seller = balance;
        } else if (_type == RefundType.Partial) {
            // 50% refund
            (uint256 half, uint256 rem) = split(balance);
            seller = half;
            buyer = half;
            protocol = rem;
        } else {
            // 100% refund (less moderator fee)
            buyer = balance;
        }
    }
}
