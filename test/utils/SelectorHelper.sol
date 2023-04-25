// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "../../lib/forge-std/src/Test.sol";

import "../../lib/solidity-stringutils/strings.sol";

import "../../src/diamond/interfaces/IDiamondLoupe.sol";

abstract contract SelectorHelper is Test {
    using strings for *;

    // return array of function selectors for given facet name
    function generateSelectors(string memory _facetName)
        internal
        returns (bytes4[] memory selectors)
    {
        //get string of contract methods
        string[] memory cmd = new string[](4);
        cmd[0] = "forge";
        cmd[1] = "inspect";
        cmd[2] = _facetName;
        cmd[3] = "methods";
        bytes memory res = vm.ffi(cmd);
        string memory st = string(res);

        // extract function signatures and take first 4 bytes of keccak
        strings.slice memory s = st.toSlice();
        strings.slice memory delim = ":".toSlice();
        strings.slice memory delim2 = ",".toSlice();
        selectors = new bytes4[]((s.count(delim)));
        for (uint256 i = 0; i < selectors.length; i++) {
            s.split('"'.toSlice());
            selectors[i] = bytes4(s.split(delim).until('"'.toSlice()).keccak());
            s.split(delim2);
        }
        return selectors;
    }

    function getAllSelectors(address diamondAddress)
        public
        view
        returns (bytes4[] memory)
    {
        IDiamondLoupe.Facet[] memory facetList =
            IDiamondLoupe(diamondAddress).facets();

        uint256 len = 0;
        for (uint256 i = 0; i < facetList.length; i++) {
            len += facetList[i].functionSelectors.length;
        }

        uint256 pos = 0;
        bytes4[] memory selectors = new bytes4[](len);
        for (uint256 i = 0; i < facetList.length; i++) {
            for (uint256 j = 0; j < facetList[i].functionSelectors.length; j++) {
                selectors[pos] = facetList[i].functionSelectors[j];
                pos += 1;
            }
        }
        return selectors;
    }
}
