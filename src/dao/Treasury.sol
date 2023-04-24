// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: © 2023 The MITRE Corporation

pragma solidity 0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";

// TODO: make multisig
contract Treasury {
    address public immutable owner;
    address public immutable usdcAddress;

    constructor(address _usdc) {
        owner = msg.sender;
        usdcAddress = _usdc;
    }

    function balance() public view returns (uint256 value) {
        value = ERC20(usdcAddress).balanceOf(address(this));
    }
}
