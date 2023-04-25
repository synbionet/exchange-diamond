// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {console} from "forge-std/Test.sol";

struct MyArgs {
    address bob;
    uint256 two;
}

contract Sample {
    function doit(address bob, uint256 two) public view returns (address, uint256) {
        console.log("CALLED");
        return (bob, two);
    }

    function hello(uint256 v, uint256 x) public pure returns (uint256 val) {
        val = x + v + 10;
    }

    function again(MyArgs memory _args) public pure returns (address, uint256) {
        return (_args.bob, _args.two);
    }
}

contract EncodingTest is Test {
    uint256 public num;
    address public name;
    Sample s;

    function setUp() public {
        s = new Sample();
    }

    function test_encode_decode() public {
        MyArgs memory a = MyArgs({bob: address(0x1), two: 3});

        bytes memory cdata = abi.encodeWithSignature("again((address,uint256))", a);

        (bool success, bytes memory result) = address(s).delegatecall(cdata);
        assertTrue(success);

        (address b, uint256 r) = abi.decode(result, (address, uint256));
        assertEq(r, 3);
        assertEq(address(0x1), b);
    }
}
