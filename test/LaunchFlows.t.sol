// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPEPEToken} from "../src/SPEPEToken.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev Test-only CREATE2 deployer, not a replacement for the network's launch factory.
contract TokenDeployerHarness {
    function deploy(bytes32 salt) external returns (SPEPEToken) {
        return new SPEPEToken{salt: salt}();
    }
}

/// @dev Tests ERC-20 movements at the launch boundary, not Uniswap pool accounting or Merkle proofs.
contract LaunchFlowsTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    address private constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address private constant REMAINDER_TO = 0x000000000000000000000000000000000000dEaD;
    // Local test actors only; the network creates its actual distributor during launch.
    address private constant DISTRIBUTOR = address(uint160(uint256(keccak256("test.distributor"))));
    address private constant CLAIMANT = address(uint160(uint256(keccak256("test.claimant"))));
    address private constant TRADER = address(uint160(uint256(keccak256("test.trader"))));
    address private constant ROUTER = address(uint160(uint256(keccak256("test.router"))));

    TokenDeployerHarness private factory;
    SPEPEToken private token;

    function setUp() public {
        vm.chainId(1);
        factory = new TokenDeployerHarness();
        token = factory.deploy(keccak256("test.launch"));
    }

    function test_Create2DeploymentLeavesFullSupplyWithFactory() public view {
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(factory),
                            keccak256("test.launch"),
                            keccak256(type(SPEPEToken).creationCode)
                        )
                    )
                )
            )
        );
        assertEq(address(token), predicted);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.balanceOf(POOL_MANAGER), 0);
        assertEq(token.balanceOf(REMAINDER_TO), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_LaunchAllocationClaimAndTradeTransfersArriveWhole() public {
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 9000 / 10_000;
        vm.prank(address(factory));
        assertTrue(token.transfer(DISTRIBUTOR, swarm));
        vm.prank(address(factory));
        assertTrue(token.transfer(POOL_MANAGER, pool));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(POOL_MANAGER), pool);

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.balanceOf(CLAIMANT), swarm);

        uint256 bought = 123_456e18;
        vm.prank(POOL_MANAGER);
        assertTrue(token.transfer(TRADER, bought));
        assertEq(token.balanceOf(TRADER), bought);
        assertEq(token.balanceOf(POOL_MANAGER), pool - bought);
        vm.prank(TRADER);
        assertTrue(token.transfer(POOL_MANAGER, bought));
        assertEq(token.balanceOf(TRADER), 0);
        assertEq(token.balanceOf(POOL_MANAGER), pool);

        // An approved router can also settle a trader's input into the manager.
        vm.prank(POOL_MANAGER);
        assertTrue(token.transfer(TRADER, bought));
        vm.prank(TRADER);
        assertTrue(token.approve(ROUTER, bought));
        vm.prank(ROUTER);
        assertTrue(token.transferFrom(TRADER, POOL_MANAGER, bought));
        assertEq(token.balanceOf(TRADER), 0);
        assertEq(token.allowance(TRADER, ROUTER), 0);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
        assertEq(token.balanceOf(CLAIMANT) + token.balanceOf(POOL_MANAGER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RoundingRemainderCanReachConfiguredRecipientWithoutBurning() public {
        // A single-sided liquidity calculation can consume less than its maximum budget.
        uint256 swarm = SUPPLY / 10;
        uint256 usedByPool = SUPPLY * 9000 / 10_000 - 7;
        vm.prank(address(factory));
        assertTrue(token.transfer(DISTRIBUTOR, swarm));
        vm.prank(address(factory));
        assertTrue(token.transfer(POOL_MANAGER, usedByPool));
        vm.prank(address(factory));
        assertTrue(token.transfer(REMAINDER_TO, 7));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(REMAINDER_TO), 7);
        assertEq(token.balanceOf(DISTRIBUTOR) + token.balanceOf(POOL_MANAGER) + token.balanceOf(REMAINDER_TO), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_PoolManagerCannotSpendAnUnapprovedHolderBalance() public {
        vm.prank(address(factory));
        assertTrue(token.transfer(TRADER, 100));
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, POOL_MANAGER, 0, 1));
        vm.prank(POOL_MANAGER);
        token.transferFrom(TRADER, POOL_MANAGER, 1);
        assertEq(token.balanceOf(TRADER), 100);
        vm.prank(TRADER);
        assertTrue(token.transfer(CLAIMANT, 100));
        assertEq(token.balanceOf(CLAIMANT), 100);
    }
}
