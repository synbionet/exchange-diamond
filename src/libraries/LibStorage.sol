// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {Exchange} from "../BionetTypes.sol";

struct BionetStorage {
    address usdc;
    address treasury;
    uint256 protocolFee;
    mapping(uint256 => Exchange) exchanges;
}

struct Counters {
    // Next service id
    uint256 nextServiceId;
    // Next exchange id
    uint256 nextExchangeId;
}

library LibStorage {
    bytes32 constant BIONET_STORAGE_POSITION = keccak256("bionet.storage.core");
    bytes32 constant BIONET_COUNTERS_POSITION = keccak256("bionet.storage.counters");

    function bionetStorage() internal pure returns (BionetStorage storage bns) {
        bytes32 position = BIONET_STORAGE_POSITION;
        assembly {
            bns.slot := position
        }
    }

    function bionetCounters() internal pure returns (Counters storage bcs) {
        bytes32 position = BIONET_COUNTERS_POSITION;
        assembly {
            bcs.slot := position
        }
    }
}

contract WithStorage {
    function bionetStore() internal pure returns (BionetStorage storage) {
        return LibStorage.bionetStorage();
    }

    function counters() internal pure returns (Counters storage) {
        return LibStorage.bionetCounters();
    }
}
