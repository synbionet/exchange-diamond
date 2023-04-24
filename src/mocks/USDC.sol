// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @dev Mock a dollar type stable coin
contract USDC is ERC20 {
    constructor() ERC20("USDC", "USDC", 6) {}

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }
}
