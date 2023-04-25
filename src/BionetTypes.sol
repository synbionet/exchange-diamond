// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

// ** default timers used in the protocol **
// How long the buyer has to commit to the offer
uint256 constant OFFER_EXPIRES = 15 days;
// Max time to resolve a dispute
uint256 constant RESOLVE_EXPIRES = 30 days;

/// @dev The calldata to Exchange.initialize()
/// TODO: Add Service info
struct ExchangeArgs {
    address buyer;
    address moderator;
    uint16 moderatorPercentage;
    uint128 price;
    uint256 disputeTimerValue;
}

enum ExchangeState {
    Offer,
    Fund,
    Dispute,
    Resolve,
    Complete,
    Void
}

struct Exchange {
    uint256 id;
    uint256 serviceId;
    ExchangeState state;
    address buyer;
    address seller;
    address moderator;
    uint256 price;
    uint16 moderatorPercentage;
    RefundType refundType;
    uint256 disputeTimerValue;
    uint256 offerExpires;
    uint256 disputeExpires;
    uint256 resolveExpires;
    string uri;
}

/// @dev Calldata to Exchange.Fund.  Information used to sign an ERC20 permit
struct ExchangePermitArgs {
    uint8 v;
    bytes32 r;
    bytes32 s;
    uint256 validFor;
}

/// @dev Refund selected by the moderator
/// None = no refund
/// Partial = 50% refund
/// Full = full refund of 'price'
enum RefundType {
    None,
    Partial,
    Full
}
