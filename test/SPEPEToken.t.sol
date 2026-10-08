// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SPEPEToken} from "../src/SPEPEToken.sol";
import {TestBase, Vm} from "./support/TestBase.sol";

contract RejectingReceiver {
    fallback() external {
        revert("ERC-20 recipients must not be called");
    }
}

contract SPEPETokenTest is TestBase {
    uint256 private constant SUPPLY = 1_000_000_000e18;
    address private constant ALICE = address(uint160(uint256(keccak256("test.alice"))));
    address private constant BOB = address(uint160(uint256(keccak256("test.bob"))));
    address private constant SPENDER = address(uint160(uint256(keccak256("test.spender"))));

    SPEPEToken private token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SPEPEToken();
    }

    function test_MetadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(keccak256(bytes(token.name())), keccak256("Swarm Pepe"));
        assertEq(keccak256(bytes(token.symbol())), keccak256("SPEPE"));
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsExactlyOneMintForWholeSupply() public {
        vm.recordLogs();
        SPEPEToken fresh = new SPEPEToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_WholeSupplyCanMoveInOneTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, SUPPLY);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_SelfTransferPreservesEntireBalanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransfersDoNotCallRecipient() public {
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 42));
        assertEq(token.balanceOf(address(receiver)), 42);
    }

    function test_RevertTransferAboveBalanceIsAtomic() public {
        vm.expectRevert(
            abi.encodeWithSelector(SPEPEToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(ALICE, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_RevertSelfTransferAboveBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SPEPEToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(address(this), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertTransferToZeroEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertZeroSender() public {
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
    }

    function test_ApprovalEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100);
        assertTrue(token.approve(SPENDER, 100));
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertTrue(token.approve(SPENDER, 12));
        assertEq(token.allowance(address(this), SPENDER), 12);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertApprovalToZero() public {
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_RevertApprovalFromZero() public {
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 1);
    }

    function test_TransferFromSpendsFiniteAllowanceExactly() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 40);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 40));
        assertEq(token.allowance(address(this), SPENDER), 60);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 60));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 100);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
    }

    function test_UnlimitedAllowanceSurvivesRepeatedSpending() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 100));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 100));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
    }

    function test_DelegatedSelfTransferConsumesAllowanceButPreservesBalance() public {
        assertTrue(token.approve(SPENDER, SUPPLY));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowanceAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_RevertTransferFromInsufficientAllowanceIsAtomic() public {
        assertTrue(token.approve(SPENDER, 10));
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, SPENDER, 10, 11));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 11);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_RevertTransferFromInsufficientBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 100));
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientBalance.selector, ALICE, 0, 100));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 100);
        assertEq(token.allowance(ALICE, SPENDER), 100);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_RevertTransferFromToZeroRestoresAllowance() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 100);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RevertTransferFromZeroAddressEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_DeployerCannotTakeHolderTokensWithoutApproval() public {
        assertTrue(token.transfer(ALICE, 100));
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_AllowanceIsSpecificToSpenderAndHolder() public {
        assertTrue(token.approve(SPENDER, 100));
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertTrue(token.transfer(ALICE, 100));
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 100);
        assertEq(token.balanceOf(ALICE), 100);
    }

    function test_TransferFromSelfStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(SPEPEToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
    }

    function test_NoAdministrativeMintBurnOrUpgradeEntryPoints() public {
        assertTrue(token.transfer(ALICE, 100));
        bytes[] memory calls = new bytes[](17);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 100);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 100);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[5] = abi.encodeWithSignature("owner()");
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[7] = abi.encodeWithSignature("pause()");
        calls[8] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[9] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[10] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[11] = abi.encodeWithSignature("setFee(uint256)", 100);
        calls[12] = abi.encodeWithSignature("setMinter(address)", BOB);
        calls[13] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[14] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[15] = abi.encodeWithSignature("setOwner(address)", BOB);
        calls[16] = abi.encodeWithSignature("disableTransfers()");
        for (uint256 i; i < calls.length; ++i) {
            (bool fromDeployer,) = address(token).call(calls[i]);
            assertTrue(!fromDeployer);
            vm.prank(BOB);
            (bool fromStranger,) = address(token).call(calls[i]);
            assertTrue(!fromStranger);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
        assertEq(token.balanceOf(BOB), 100);
    }

    function test_RejectsEtherAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool paid,) = address(token).call{value: 1}("");
        assertTrue(!paid);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertTrue(!unknown);
        (bool payableTransfer,) = address(token).call{value: 1}(abi.encodeCall(token.transfer, (ALICE, 1)));
        assertTrue(!payableTransfer);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory code = address(token).code;
        assertTrue(code.length > 0 && code.length <= 24_576);
        for (uint256 i; i < code.length; ++i) {
            uint8 opcode = uint8(code[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf2 && opcode != 0xf4 && opcode != 0xff);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransfersRoundTripWithoutLoss(uint256 seed) public {
        uint256 amount = seed % (SUPPLY + 1);
        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(ALICE), 0);
        vm.prank(BOB);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AllowanceConservation(uint256 grantSeed, uint256 spendSeed) public {
        uint256 grant = grantSeed % (SUPPLY + 1);
        uint256 spend = spendSeed % (grant + 1);
        assertTrue(token.approve(SPENDER, grant));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spend));
        assertEq(token.allowance(address(this), SPENDER) + spend, grant);
        assertEq(token.balanceOf(ALICE), spend);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferAboveBalanceReverts(uint256 seed) public {
        uint256 invalidAmount = SUPPLY + 1 + seed % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(SPEPEToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, invalidAmount)
        );
        token.transfer(ALICE, invalidAmount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
