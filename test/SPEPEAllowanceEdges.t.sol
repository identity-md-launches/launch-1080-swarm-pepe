// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPEPEToken} from "../src/SPEPEToken.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev Extends the existing examples with full-width allowances and adversarial ABI inputs.
contract SPEPEAllowanceEdgesTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    uint256 private constant FUNDED = SUPPLY / 4;
    address private constant HOLDER = address(uint160(uint256(keccak256("edges.holder"))));
    address private constant RECIPIENT = address(uint160(uint256(keccak256("edges.recipient"))));
    address private constant SPENDER = address(uint160(uint256(keccak256("edges.spender"))));
    address private constant OTHER_SPENDER = address(uint160(uint256(keccak256("edges.other-spender"))));

    SPEPEToken private token;

    function setUp() public {
        token = new SPEPEToken();
        assertTrue(token.transfer(HOLDER, FUNDED));
        vm.prank(HOLDER);
        assertTrue(token.approve(SPENDER, FUNDED));
        vm.prank(HOLDER);
        assertTrue(token.approve(OTHER_SPENDER, 17));
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_FailedSpendRestoresFiniteOrInfiniteAllowance(uint256 seed, bool infinite) public {
        uint256 amount = FUNDED + 1 + seed % (type(uint256).max - FUNDED);
        uint256 approval = infinite ? type(uint256).max : amount;
        vm.prank(HOLDER);
        assertTrue(token.approve(SPENDER, approval));
        bytes32 beforeState = _state();

        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientBalance.selector, HOLDER, FUNDED, amount));
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, RECIPIENT, amount);
        assertEq(_state(), beforeState);

        // A reverted overspend must not prevent a later affordable spend.
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, RECIPIENT, FUNDED));
        assertEq(token.balanceOf(HOLDER), 0);
        assertEq(token.balanceOf(RECIPIENT), FUNDED);
        assertEq(token.allowance(HOLDER, SPENDER), approval == type(uint256).max ? approval : approval - FUNDED);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_InfiniteApprovalCanBeReplacedAndThenRevoked(uint256 seed) public {
        uint256 replacement = seed % FUNDED;
        vm.prank(HOLDER);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(HOLDER);
        assertTrue(token.approve(SPENDER, replacement));
        bytes32 beforeState = _state();

        vm.expectRevert(
            abi.encodeWithSelector(
                SPEPEToken.ERC20InsufficientAllowance.selector, SPENDER, replacement, replacement + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, RECIPIENT, replacement + 1);
        assertEq(_state(), beforeState);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, RECIPIENT, replacement));
        assertEq(token.allowance(HOLDER, SPENDER), 0);
        vm.prank(HOLDER);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(HOLDER);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, RECIPIENT, 1);
        assertEq(token.balanceOf(HOLDER), FUNDED - replacement);
        assertEq(token.balanceOf(RECIPIENT), replacement);
        assertEq(token.allowance(HOLDER, OTHER_SPENDER), 17);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_MaxMinusOneAllowanceIsFinite(uint256 seed) public {
        uint256 amount = 1 + seed % FUNDED;
        vm.prank(HOLDER);
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, RECIPIENT, amount));
        assertEq(token.allowance(HOLDER, SPENDER), type(uint256).max - 1 - amount);
        assertEq(token.allowance(HOLDER, OTHER_SPENDER), 17);
        assertEq(token.balanceOf(HOLDER) + token.balanceOf(RECIPIENT), FUNDED);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_CompetingSpendersCannotSpendTheSameBalanceTwice(uint256 seed) public {
        uint256 firstSpend = 1 + seed % FUNDED;
        vm.prank(HOLDER);
        assertTrue(token.approve(OTHER_SPENDER, FUNDED));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, RECIPIENT, firstSpend));
        assertEq(token.allowance(HOLDER, OTHER_SPENDER), FUNDED);
        bytes32 beforeState = _state();

        vm.expectRevert(
            abi.encodeWithSelector(SPEPEToken.ERC20InsufficientBalance.selector, HOLDER, FUNDED - firstSpend, FUNDED)
        );
        vm.prank(OTHER_SPENDER);
        token.transferFrom(HOLDER, RECIPIENT, FUNDED);
        assertEq(_state(), beforeState);

        vm.prank(OTHER_SPENDER);
        assertTrue(token.transferFrom(HOLDER, RECIPIENT, FUNDED - firstSpend));
        assertEq(token.balanceOf(HOLDER), 0);
        assertEq(token.balanceOf(RECIPIENT), FUNDED);
        assertEq(token.allowance(HOLDER, SPENDER), FUNDED - firstSpend);
        assertEq(token.allowance(HOLDER, OTHER_SPENDER), firstSpend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TruncatedMutationCalldataIsRejected(uint8 method, uint8 cutSeed) public {
        bytes memory valid;
        address caller;
        if (method % 3 == 0) {
            valid = abi.encodeCall(token.transfer, (RECIPIENT, 1));
            caller = HOLDER;
        } else if (method % 3 == 1) {
            valid = abi.encodeCall(token.approve, (SPENDER, 1));
            caller = HOLDER;
        } else {
            valid = abi.encodeCall(token.transferFrom, (HOLDER, RECIPIENT, 1));
            caller = SPENDER;
        }
        bytes memory truncated = new bytes(uint256(cutSeed) % valid.length);
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = valid[i];
        }
        _rejectWithoutChanges(caller, truncated);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_NonCanonicalAddressWordsAreRejected(uint96 dirtyBits) public {
        uint256 upper = uint256(dirtyBits == 0 ? 1 : dirtyBits) << 160;
        uint256 dirtyRecipient = upper | uint256(uint160(RECIPIENT));
        uint256 dirtyHolder = upper | uint256(uint160(HOLDER));
        uint256 dirtySpender = upper | uint256(uint160(SPENDER));
        _rejectWithoutChanges(HOLDER, abi.encodeWithSelector(token.transfer.selector, dirtyRecipient, 1));
        _rejectWithoutChanges(HOLDER, abi.encodeWithSelector(token.approve.selector, dirtySpender, 1));
        _rejectWithoutChanges(SPENDER, abi.encodeWithSelector(token.transferFrom.selector, dirtyHolder, RECIPIENT, 1));
        _rejectWithoutChanges(SPENDER, abi.encodeWithSelector(token.transferFrom.selector, HOLDER, dirtyRecipient, 1));
    }

    function test_ZeroRecipientRejectsZeroDelegatedSpendForBothAllowanceKinds() public {
        for (uint256 i; i < 2; ++i) {
            vm.prank(HOLDER);
            assertTrue(token.approve(SPENDER, i == 0 ? 0 : type(uint256).max));
            bytes32 beforeState = _state();
            vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(SPENDER);
            token.transferFrom(HOLDER, address(0), 0);
            assertEq(_state(), beforeState);
        }
    }

    function test_EveryEntryPointRejectsEtherWithoutChangingState() public {
        bytes[] memory calls = new bytes[](9);
        calls[0] = abi.encodeCall(token.name, ());
        calls[1] = abi.encodeCall(token.symbol, ());
        calls[2] = abi.encodeCall(token.decimals, ());
        calls[3] = abi.encodeCall(token.totalSupply, ());
        calls[4] = abi.encodeCall(token.balanceOf, (HOLDER));
        calls[5] = abi.encodeCall(token.allowance, (HOLDER, SPENDER));
        calls[6] = abi.encodeCall(token.transfer, (RECIPIENT, 1));
        calls[7] = abi.encodeCall(token.approve, (SPENDER, 1));
        calls[8] = abi.encodeCall(token.transferFrom, (HOLDER, RECIPIENT, 1));
        vm.deal(HOLDER, 1);
        vm.deal(SPENDER, 1);
        bytes32 beforeState = _state();
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(i == 8 ? SPENDER : HOLDER);
            (bool ok,) = address(token).call{value: 1}(calls[i]);
            assertTrue(!ok);
            assertEq(_state(), beforeState);
        }
        assertEq(address(token).balance, 0);
        assertEq(HOLDER.balance, 1);
        assertEq(SPENDER.balance, 1);
    }

    function _rejectWithoutChanges(address caller, bytes memory data) private {
        bytes32 beforeState = _state();
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        assertTrue(!ok);
        assertEq(_state(), beforeState);
    }

    function _state() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                token.totalSupply(),
                token.balanceOf(address(this)),
                token.balanceOf(HOLDER),
                token.balanceOf(RECIPIENT),
                token.balanceOf(SPENDER),
                token.balanceOf(OTHER_SPENDER),
                token.balanceOf(address(0)),
                token.balanceOf(address(token)),
                token.allowance(HOLDER, SPENDER),
                token.allowance(HOLDER, OTHER_SPENDER)
            )
        );
    }
}
