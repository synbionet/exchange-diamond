// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {WithStorage} from "../libraries/LibStorage.sol";
import {Exchange, ExchangeState} from "../BionetTypes.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @dev Getters across Facets
contract BionetGettersFacet is WithStorage {
    /// @dev Get an exchange by Id
    /// @param _exchangeId the id of the exchange
    /// @return info a memory version of the Exchange
    function getExchange(uint256 _exchangeId)
        external
        view
        returns (Exchange memory info)
    {
        info = bionetStore().exchanges[_exchangeId];
    }

    function getUsdcAddress() public view returns (address u) {
        u = bionetStore().usdc;
    }

    function getUsdcBalance(address who) public view returns (uint256 bal) {
        ERC20 usdc = ERC20(getUsdcAddress());
        bal = usdc.balanceOf(who);
    }

    function getTreasuryAddress() public view returns (address t) {
        t = bionetStore().treasury;
    }

    function getTreasureBalance() external view returns (uint256 bal) {
        bal = getUsdcBalance(address(this));
    }
}
