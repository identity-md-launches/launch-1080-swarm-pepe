// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Only the Foundry cheatcodes used by this suite; no downloaded test dependencies.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address msgSender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool topic1, bool topic2, bool topic3, bool data, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function deal(address account, uint256 balance) external;
    function chainId(uint256 newChainId) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "uint equality assertion failed");
    }

    function assertEq(address actual, address expected) internal pure {
        require(actual == expected, "address equality assertion failed");
    }

    function assertEq(bytes32 actual, bytes32 expected) internal pure {
        require(actual == expected, "bytes32 equality assertion failed");
    }

    function assertTrue(bool condition) internal pure {
        require(condition, "boolean assertion failed");
    }
}
