// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPEPEToken} from "../src/SPEPEToken.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev Independent expected balances and approvals, including deliberately rejected calls.
/// Inputs are bounded using the model, never the implementation's current balances/allowances.
contract SPEPELedgerHandler is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    uint256 private constant ACTOR_COUNT = 5;
    SPEPEToken public immutable token;
    address[7] private accounts;
    mapping(address => uint256) private expectedBalance;
    mapping(address => mapping(address => uint256)) private expectedAllowance;

    constructor() {
        token = new SPEPEToken();
        accounts[0] = address(this); // Actual constructor caller, also exercises deployer privileges.
        accounts[1] = address(uint160(uint256(keccak256("ledger.alice"))));
        accounts[2] = address(uint160(uint256(keccak256("ledger.bob"))));
        accounts[3] = 0x000000000004444c5dc75cB358380D2e3dE08A90;
        accounts[4] = address(uint160(uint256(keccak256("ledger.distributor"))));
        accounts[5] = address(token); // Passive recipient; the token cannot initiate transfers.
        accounts[6] = address(0);
        expectedBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            assertTrue(token.transfer(accounts[i], SUPPLY / 10));
            expectedBalance[accounts[i]] = SUPPLY / 10;
            expectedBalance[address(this)] -= SUPPLY / 10;
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 seed, uint8 mode) external {
        address from = accounts[fromSeed % ACTOR_COUNT];
        address to = accounts[toSeed % accounts.length];
        uint256 value = _amount(seed, mode, expectedBalance[from]);
        bool allowed = to != address(0) && value <= expectedBalance[from];
        _call(from, abi.encodeCall(token.transfer, (to, value)), allowed);
        if (allowed) _move(from, to, value);
    }

    function approve(uint256 holderSeed, uint256 spenderSeed, uint256 seed, uint8 mode) external {
        address holder = accounts[holderSeed % ACTOR_COUNT];
        address spender = accounts[spenderSeed % accounts.length];
        uint256 value;
        uint8 choice = mode % 7;
        if (choice == 0) value = 0;
        else if (choice == 1) value = 1;
        else if (choice == 2) value = expectedBalance[holder];
        else if (choice == 3) value = SUPPLY;
        else if (choice == 4) value = type(uint256).max - 1;
        else if (choice == 5) value = type(uint256).max;
        else value = seed;
        bool allowed = spender != address(0);
        _call(holder, abi.encodeCall(token.approve, (spender, value)), allowed);
        if (allowed) expectedAllowance[holder][spender] = value;
    }

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 seed, uint8 mode) external {
        address from = accounts[fromSeed % accounts.length];
        address spender = accounts[spenderSeed % ACTOR_COUNT];
        address to = accounts[toSeed % accounts.length];
        uint256 approval = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 limit = approval < balance ? approval : balance;
        uint256 value = _amount(seed, mode, limit);
        bool allowed = from != address(0) && to != address(0) && value <= balance && value <= approval;
        _call(spender, abi.encodeCall(token.transferFrom, (from, to, value)), allowed);
        if (allowed) {
            _move(from, to, value);
            if (approval != type(uint256).max) expectedAllowance[from][spender] = approval - value;
        }
    }

    function attemptAdmin(uint256 callerSeed, uint256 actionSeed, uint256 holderSeed) external {
        address caller = accounts[callerSeed % ACTOR_COUNT];
        address holder = accounts[holderSeed % ACTOR_COUNT];
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", holder, SUPPLY);
        calls[1] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[2] = abi.encodeWithSignature("burnFrom(address,uint256)", holder, 1);
        calls[3] = abi.encodeWithSignature("pause()");
        calls[4] = abi.encodeWithSignature("blacklist(address)", holder);
        calls[5] = abi.encodeWithSignature("seize(address)", holder);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", holder);
        calls[7] = abi.encodeWithSignature("initialize(address)", holder);
        _call(caller, calls[actionSeed % calls.length], false);
    }

    function assertModel() external view {
        uint256 sum;
        for (uint256 i; i < accounts.length; ++i) {
            address holder = accounts[i];
            uint256 actual = token.balanceOf(holder);
            require(actual == expectedBalance[holder], "holder balance differs from model");
            sum += actual;
            for (uint256 j; j < accounts.length; ++j) {
                address spender = accounts[j];
                require(
                    token.allowance(holder, spender) == expectedAllowance[holder][spender],
                    "allowance differs from model"
                );
            }
        }
        require(sum == SUPPLY, "balances do not conserve supply");
        require(token.totalSupply() == SUPPLY, "supply changed");
        require(token.balanceOf(address(0)) == 0, "zero address received tokens");
    }

    function _amount(uint256 seed, uint8 mode, uint256 limit) private pure returns (uint256) {
        uint8 choice = mode % 7;
        if (choice == 0) return 0;
        if (choice == 1) return 1;
        if (choice == 2) return limit;
        if (choice == 3) return limit + 1; // limit is always at most the fixed supply.
        if (choice == 4) return type(uint256).max;
        if (choice == 5) return seed;
        return seed % (limit + 1);
    }

    function _move(address from, address to, uint256 value) private {
        expectedBalance[from] -= value;
        expectedBalance[to] += value;
    }

    function _call(address caller, bytes memory data, bool expectedSuccess) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        require(success == expectedSuccess, "unexpected call success or failure");
        if (success) require(result.length == 32 && abi.decode(result, (bool)), "missing ERC-20 true return");
    }
}

contract SPEPELedgerInvariantTest is TestBase {
    SPEPELedgerHandler private handler;

    function setUp() public {
        vm.chainId(1);
        handler = new SPEPELedgerHandler();
        handler.assertModel();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_EveryBalanceAndAllowanceMatchesModel() public view {
        handler.assertModel();
    }
}
