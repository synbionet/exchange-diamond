// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {
    Exchange,
    ExchangeArgs,
    ExchangeState,
    OFFER_EXPIRES,
    RESOLVE_EXPIRES,
    ExchangePermitArgs,
    RefundType
} from "../BionetTypes.sol";
import {LibFee} from "../libraries/LibFee.sol";
import {WithStorage} from "../libraries/LibStorage.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

///
/// @dev This facet defines the fair exchange protocol for services.
/// It works through a series of state transistions to manage escrowed
/// funds on behalf of a buyer and seller.
///
/// A complete description of how it works, can be found here:
/// https://github.com/synbionet/doc.synbionet/blob/main/docs/exchange.md
///
contract ExchangeFacet is WithStorage {
    /// reverts when trying to call a function in the wrong state
    error InValidState();
    /// reverts from an unauthorized caller
    error UnAuthorizedCaller();
    /// reverts on address(0x0)
    error NoZeroAddress();
    /// reverts when you try to float a bad check
    error InsufficientFunds();
    /// reverts when there's no moderator expected
    error NoModeratorSelected();
    /// reverts if missing the required dispute time setting
    error MissingDisputeExpiration();
    /// reverts if buyer tries to dispute a free (price=0) exchange
    error CantDisputeFreeStuff();

    // TODO: below still needed?
    /// reverts if user tried to trigger a timer that's still valid
    //error TimerNotExpired();
    /// revert if the timer is expired
    error TimerExpired();

    /// Called when an exchange is initialized
    event Offered(
        uint256 indexed exchangeId,
        address indexed buyer,
        address indexed seller,
        address moderator,
        uint256 when
    );
    /// When funded
    event Funded(uint256 indexed exchangeId, uint256 price, uint256 when);
    /// When disputed
    event Disputed(uint256 indexed exchangeId, uint256 when);
    /// When resolved
    event Resolved(uint256 indexed exchangeId, uint8 refundType, uint256 when);
    /// When refunded
    event Refunded(uint256 indexed exchangeId, address signer, uint256 when);
    /// When voided (offer expired)
    event Voided(uint256 indexed exchangeId, uint256 when);
    /// When completed (funds released)
    event Completed(uint256 indexed exchangeId, uint256 when);

    /// @dev Create a new Exchange. Called by the seller.
    ///
    /// Reverts if:
    ///   - buyer or seller addresses are 0x0
    ///   - the disputeTimer value is 0
    ///
    /// Emits Offered
    /// @param _args Initial exchange information
    /// @return eid the new exchange identifier
    function createOffer(ExchangeArgs calldata _args)
        external
        returns (uint256 eid)
    {
        address seller = msg.sender;
        if (_args.buyer == address(0x0) || seller == address(0x0)) {
            revert NoZeroAddress();
        }
        if (_args.disputeTimerValue == 0) revert MissingDisputeExpiration();

        eid = counters().nextExchangeId++;
        bionetStore().exchanges[eid].seller = seller;
        bionetStore().exchanges[eid].buyer = _args.buyer;
        bionetStore().exchanges[eid].price = _args.price;
        bionetStore().exchanges[eid].state = ExchangeState.Offer;
        bionetStore().exchanges[eid].disputeTimerValue = _args.disputeTimerValue;

        // timers:

        // Offer expires in 15 days
        bionetStore().exchanges[eid].offerExpires = block.timestamp + OFFER_EXPIRES;

        // Time allocated to resolve a dispute (30 days). Note: this time is updated
        // when dispute is called.  It's set as a default here to ensure it has a
        // value.
        bionetStore().exchanges[eid].resolveExpires =
            block.timestamp + RESOLVE_EXPIRES;

        // Adjust moderator information
        if (_args.price == 0) {
            // if price == 0, dispute is disabled and the moderator address
            // is set to 0x0
            bionetStore().exchanges[eid].moderator = address(0x0);
        } else {
            bionetStore().exchanges[eid].moderator = _args.moderator;
            bionetStore().exchanges[eid].moderatorPercentage =
                _args.moderatorPercentage;
        }

        emit Offered(eid, _args.buyer, seller, _args.moderator, block.timestamp);
    }

    /// @dev Check if the exchange is closed (complete or voided)
    /// @param _exchangeId the id of the exchange
    /// @return closed true | false
    function isClosed(uint256 _exchangeId) external view returns (bool closed) {
        ExchangeState state = bionetStore().exchanges[_exchangeId].state;
        if (state == ExchangeState.Complete || state == ExchangeState.Void) {
            closed = true;
        } else {
            // just being explicit
            closed = false;
        }
    }

    /// @dev Commit to an offer.  Called by the buyer recorded in the
    /// exchange offer. On success it will transition to the 'Fund' state. If the
    /// offer has expired, it will be 'Voided' - no sale.
    ///
    /// Unless this is a free sale (price == 0), The buyer authorizes the exchange
    /// to transfer funds to escrow.
    ///
    /// Reverts if:
    ///   - the caller is not the recorded buyer
    ///   - the exchange is not in the 'offer' state.
    ///   - the buyer does not have enough money to escrow 'price'
    ///
    /// Emits 'Voided' if the offer expired, otherwise 'Funded'
    ///
    /// @param _exchangeId the exchange id
    /// @param _permit signed message from buyer to authorize the escrow
    function fundOffer(uint256 _exchangeId, ExchangePermitArgs calldata _permit)
        external
    {
        Exchange storage ex = bionetStore().exchanges[_exchangeId];

        if (msg.sender != ex.buyer) revert UnAuthorizedCaller();
        if (ex.state != ExchangeState.Offer) revert InValidState();

        if (_isTimerExpired(ex.offerExpires)) {
            // offer expired
            ex.state = ExchangeState.Void;
            emit Voided(_exchangeId, block.timestamp);
        } else if (ex.price == 0) {
            ex.state = ExchangeState.Fund;
            // 'expires' is only updated here for consistency.  a zero price sale
            // has no dispute phase.
            ex.disputeExpires = block.timestamp + ex.disputeTimerValue;
            emit Funded(_exchangeId, ex.price, block.timestamp);
        } else {
            // Check the buyer has sufficient funds
            ERC20 usdc = ERC20(bionetStore().usdc);
            if (usdc.balanceOf(msg.sender) < ex.price) revert InsufficientFunds();

            ex.state = ExchangeState.Fund;
            ex.disputeExpires = block.timestamp + ex.disputeTimerValue;

            // authorize the exchange to transfer 'price' via the signed msg
            usdc.permit(
                msg.sender,
                address(this),
                ex.price,
                _permit.validFor,
                _permit.v,
                _permit.r,
                _permit.s
            );

            // transfer 'escrow' to this exchange
            SafeTransferLib.safeTransferFrom(
                usdc, msg.sender, address(this), ex.price
            );

            // Emit event
            emit Funded(_exchangeId, ex.price, block.timestamp);
        }
    }

    /// @dev Complete an exchange.  Called by the Buyer. This finalizes the exchange
    /// and releases any escrowed funds.
    ///
    /// Reverts if:
    ///   - The caller is not the recorded buyer
    ///   - The exchange is not in the 'Fund' state
    ///
    /// emit Complete
    ///
    /// @param _exchangeId the exchange id
    function complete(uint256 _exchangeId) external {
        Exchange storage ex = bionetStore().exchanges[_exchangeId];

        if (msg.sender != ex.buyer) revert UnAuthorizedCaller();
        if (ex.state != ExchangeState.Fund) revert InValidState();

        // We don't check a timer here as the effect is the same.
        paySellerAndProtocol(ex);
    }

    /// @dev Called by buyer to dispute an exchange. Changes state to
    /// the dispute phase and starts the resolution timer.
    ///
    /// Reverts if:
    ///   - caller is not the recorded buyer
    ///   - not in the state of funded
    ///   - dispute time frame has expired
    ///   - price == 0.  As fee stuff does not have a dispute phase
    ///
    /// emits Disputed
    /// @param _exchangeId the exchange id
    function dispute(uint256 _exchangeId) external {
        Exchange storage ex = bionetStore().exchanges[_exchangeId];
        if (msg.sender != ex.buyer) revert UnAuthorizedCaller();
        if (ex.state != ExchangeState.Fund) revert InValidState();
        if (_isTimerExpired(ex.disputeExpires)) revert TimerExpired();
        // Can't dispute free stuff
        if (ex.price == 0) revert CantDisputeFreeStuff();

        ex.state = ExchangeState.Dispute;
        // start and set the resolve timer
        ex.resolveExpires = block.timestamp + RESOLVE_EXPIRES;
        emit Disputed(_exchangeId, block.timestamp);
    }

    /// @dev Called by the moderator to resolve a dispute.  Require 2 of 3
    /// signatures to release funds. This call (from the moderator) counts as 1 of
    /// the required signatures. Changes the state to 'Resolve'
    ///
    /// Reverts if:
    ///   - caller is not the moderator
    ///   - not in the state of 'Dispute'
    ///   - the resolve timer has expired
    ///
    /// emits Resolved
    ///
    /// @param _exchangeId the exchange id
    /// @param _rType is the refund chosen by the moderator
    function resolve(uint256 _exchangeId, RefundType _rType) external {
        Exchange storage ex = bionetStore().exchanges[_exchangeId];
        if (msg.sender != ex.moderator) revert UnAuthorizedCaller();
        if (ex.state != ExchangeState.Dispute) revert InValidState();
        if (_isTimerExpired(ex.resolveExpires)) revert TimerExpired();

        ex.refundType = _rType;
        ex.state = ExchangeState.Resolve;

        // emit event
        emit Resolved(_exchangeId, uint8(_rType), block.timestamp);
    }

    /// @dev Called by either the buyer or seller to complete the 2 of 3 signatures
    /// needed to collect the refund.  This will calculate payouts, transfer funds
    /// and close out the exchange.
    ///
    /// Reverts if:
    ///   - caller is not the buyer or seller
    ///   - not in the 'Resolve' state
    ///   - resolve timer expired
    ///
    /// emits Refunded
    /// @param _exchangeId the exchange id
    function agreeToRefund(uint256 _exchangeId) external {
        Exchange storage ex = bionetStore().exchanges[_exchangeId];

        bool valid = msg.sender != ex.buyer || msg.sender != ex.seller;
        if (!valid) revert UnAuthorizedCaller();
        if (ex.state != ExchangeState.Resolve) revert InValidState();
        if (_isTimerExpired(ex.resolveExpires)) revert TimerExpired();

        // Process the refund. We received 2 or 3 'signatures' Release funds based on
        // refund type
        (
            uint256 dueSeller,
            uint256 dueBuyer,
            uint256 dueModerator,
            uint256 dueProtocol
        ) = LibFee.refund(ex.refundType, ex.moderatorPercentage, ex.price);
        releaseFunds(ex, dueSeller, dueBuyer, dueModerator, dueProtocol);

        emit Refunded(_exchangeId, msg.sender, block.timestamp);
    }

    /// @dev Update timers in the event of no activity. Called by the buyer or seller
    /// This is fail-safe to keep the exchange moving forward.
    ///
    /// A client can use 'callStatic' in ethers.js to simulate this call and
    /// determine whether trigger will fire anything (return true or false).  For
    /// example, if 'callStatic' returns true, you know a timer is expired and can
    /// then make the call without wasting a transaction.
    ///
    /// Reverts if:
    ///   - Caller is not the buyer or seller of the exchange
    ///
    /// emits Voided or Completed
    ///
    /// @param _exchangeId the exchange id
    /// @return bool true if updated, false otherwise
    function triggerTimer(uint256 _exchangeId) external returns (bool) {
        Exchange storage ex = bionetStore().exchanges[_exchangeId];

        bool valid = msg.sender != ex.buyer || msg.sender != ex.seller;
        if (!valid) revert UnAuthorizedCaller();

        // if the exchanged is already 'closed' there's nothing else to check
        if (ex.state == ExchangeState.Complete || ex.state == ExchangeState.Void) {
            return false;
        }

        // if in 'Offer' and timer expired -> Void
        if (ex.state == ExchangeState.Offer) {
            if (_isTimerExpired(ex.offerExpires)) {
                ex.state = ExchangeState.Void;
                emit Voided(ex.id, block.timestamp);
                return true;
            }
            return false;
        }

        // if in 'Fund' and timer expired -> finalize
        if (ex.state == ExchangeState.Fund) {
            if (_isTimerExpired(ex.disputeExpires)) {
                paySellerAndProtocol(ex);
                return true;
            }
            return false;
        }

        // if in 'Dispute' or 'Resolve' an timer expired -> finalize
        if (ex.state == ExchangeState.Dispute || ex.state == ExchangeState.Resolve) {
            if (_isTimerExpired(ex.resolveExpires)) {
                paySellerAndProtocol(ex);
                return true;
            }
            return false;
        }
        return false;
    }

    /// ****
    /// Internal functions
    /// ****

    /// @dev Check if the given timestamp is older than the current time.
    function _isTimerExpired(uint256 ts) internal view returns (bool expired) {
        expired = block.timestamp > ts;
    }

    /// @dev Finalize the exchange and release funds if price != 0
    function paySellerAndProtocol(Exchange storage ex) internal {
        if (ex.price != 0) {
            (uint256 dueSeller, uint256 dueProtocol) = LibFee.payoutAndFee(ex.price);
            releaseFunds(ex, dueSeller, 0, 0, dueProtocol);
        } else {
            ex.state = ExchangeState.Complete;
            emit Completed(ex.id, block.timestamp);
        }
    }

    /// @dev Release funds to all parties as required. Transfers stablecoin tokens
    function releaseFunds(
        Exchange storage ex,
        uint256 _sellerAmt,
        uint256 _buyerAmt,
        uint256 _modAmt,
        uint256 _protoAmt
    ) internal {
        ERC20 usdc = ERC20(bionetStore().usdc);
        // set state to complete
        ex.state = ExchangeState.Complete;

        // Payday!
        if (_sellerAmt > 0) {
            SafeTransferLib.safeTransfer(usdc, ex.seller, _sellerAmt);
        }
        if (_buyerAmt > 0) SafeTransferLib.safeTransfer(usdc, ex.buyer, _buyerAmt);
        if (_modAmt > 0) SafeTransferLib.safeTransfer(usdc, ex.moderator, _modAmt);
        if (_protoAmt > 0) {
            SafeTransferLib.safeTransfer(usdc, bionetStore().treasury, _protoAmt);
        }

        emit Completed(ex.id, block.timestamp);
    }
}
