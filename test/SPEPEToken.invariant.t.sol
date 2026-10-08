// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPEPEToken} from "../src/SPEPEToken.sol";
import {TestBase} from "./support/TestBase.sol";

contract TokenHandler is TestBase {
    SPEPEToken private immutable token;
    address[4] private actors;

    constructor(SPEPEToken token_) {
        token = token_;
        actors[0] = address(this);
        for (uint256 i = 1; i < actors.length; ++i) {
            actors[i] = address(uint160(uint256(keccak256(abi.encode("invariant.actor", i)))));
        }
    }

    function actor(uint256 index) external view returns (address) {
        return actors[index];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 valueSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 value = valueSeed % (token.balanceOf(from) + 1);
        vm.prank(from);
        assertTrue(token.transfer(to, value));
    }

    function approve(uint256 holderSeed, uint256 spenderSeed, uint256 value, bool unlimited) external {
        address holder = actors[holderSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(holder);
        assertTrue(token.approve(spender, unlimited ? type(uint256).max : value));
    }

    function transferFrom(uint256 holderSeed, uint256 spenderSeed, uint256 toSeed, uint256 valueSeed) external {
        address holder = actors[holderSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 available = token.allowance(holder, spender);
        uint256 maxValue = token.balanceOf(holder);
        if (available < maxValue) maxValue = available;
        uint256 value = valueSeed % (maxValue + 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, to, value));
        assertEq(token.allowance(holder, spender), available == type(uint256).max ? available : available - value);
    }

    function overspend(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBalance = token.balanceOf(from);
        uint256 toBalance = token.balanceOf(to);
        vm.prank(from);
        (bool success,) = address(token).call(abi.encodeCall(token.transfer, (to, fromBalance + 1)));
        assertTrue(!success);
        assertEq(token.balanceOf(from), fromBalance);
        assertEq(token.balanceOf(to), toBalance);
    }
}

contract SPEPETokenInvariantTest is TestBase {
    SPEPEToken private token;
    TokenHandler private handler;

    function setUp() public {
        token = new SPEPEToken();
        handler = new TokenHandler(token);
        assertTrue(token.transfer(address(handler), token.totalSupply()));
    }

    /// @dev Foundry discovers this target list without a forge-std dependency.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_FixedSupplyEqualsSumOfAllHolderBalances() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            sum += token.balanceOf(handler.actor(i));
        }
        assertEq(sum, 1_000_000_000e18);
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
