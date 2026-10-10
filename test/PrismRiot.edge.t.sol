// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PrismRiot} from "src/PrismRiot.sol";

/// @dev The relay is the spender seen by the token, regardless of transaction origin.
contract PrismRiotSpenderRelay {
    function spend(PrismRiot token, address from, address to, uint256 amount) external returns (bool) {
        return token.transferFrom(from, to, amount);
    }
}

/// @dev A contract holder that rejects every callback but can send its own tokens.
contract PrismRiotContractHolder {
    function move(PrismRiot token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }

    fallback() external {
        revert("unexpected receiver callback");
    }
}

/// @notice Boundary and sequence coverage complementing the original deployment/ERC-20 suite.
/// forge-config: default.fuzz.runs = 1000
contract PrismRiotEdgeTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    PrismRiot private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new PrismRiot();
        alice = makeAddr("edge-alice");
        bob = makeAddr("edge-bob");
        spender = makeAddr("edge-spender");
    }

    function test_OneWeiCanMakeADirectAndDelegatedRoundTrip() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumTransferRevertsWithBalanceError() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumAllowanceDoesNotAuthorizeMoreThanTheBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeReducedAndRevoked() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 1));
        assertEq(token.allowance(address(this), spender), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);

        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExhaustedAllowanceCannotBeSpentTwice() public {
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_HolderNeedsItsOwnApprovalForTransferFrom() public {
        token.transfer(alice, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(alice);
        assertTrue(token.approve(alice, 1));
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroValueApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferStillRejectsZeroRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SpenderIsImmediateCallerRegardlessOfTransactionOrigin() public {
        PrismRiotSpenderRelay relay = new PrismRiotSpenderRelay();
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(alice, 1);

        // Origin has self-approval, but the contract making the token call does not.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(relay), 0, 1));
        vm.prank(alice, alice);
        relay.spend(token, alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, alice), 1);
        assertEq(token.allowance(alice, address(relay)), 0);

        vm.prank(alice);
        assertTrue(token.approve(address(relay), 1));
        vm.prank(spender, spender);
        assertTrue(relay.spend(token, alice, bob, 1));
        assertEq(token.allowance(alice, address(relay)), 0);
        assertEq(token.allowance(alice, alice), 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ContractHolderCanReceiveAndReturnEntireSupplyWithoutCallbacks() public {
        PrismRiotContractHolder holder = new PrismRiotContractHolder();
        assertTrue(token.transfer(address(holder), SUPPLY));
        assertEq(token.balanceOf(address(holder)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertTrue(holder.move(token, address(this), SUPPLY));
        assertEq(token.balanceOf(address(holder)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_AllowanceIsScopedToOwnerAndSpender(uint256 amount, uint256 otherAllowance) public {
        amount = bound(amount, 1, SUPPLY / 2);
        token.transfer(alice, SUPPLY / 2);
        token.approve(spender, amount);
        vm.prank(alice);
        token.approve(bob, otherAllowance);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, amount));
        vm.prank(bob);
        token.transferFrom(address(this), bob, amount);
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.allowance(alice, bob), otherAllowance);
        assertEq(token.balanceOf(address(this)), SUPPLY / 2);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.allowance(alice, bob), otherAllowance);
        assertEq(token.balanceOf(address(this)), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(alice), SUPPLY / 2);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ReducedApprovalCannotSpendTheOldRemainder(uint256 grant, uint256 spent) public {
        grant = bound(grant, 2, SUPPLY);
        spent = bound(spent, 1, grant - 1);
        token.approve(spender, grant);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        uint256 oldRemainder = grant - spent;
        assertTrue(token.approve(spender, oldRemainder - 1));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, oldRemainder - 1, oldRemainder
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, oldRemainder);
        assertEq(token.allowance(address(this), spender), oldRemainder - 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendRemainsUsableAfterFunding(uint256 held, uint256 requested, bool infinite) public {
        held = bound(held, 0, SUPPLY - 1);
        requested = bound(requested, held + 1, SUPPLY);
        uint256 grant = infinite ? type(uint256).max : requested;
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, grant);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested));
        vm.prank(spender);
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, spender), grant);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);

        assertTrue(token.transfer(alice, requested - held));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, requested));
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), requested);
        assertEq(token.balanceOf(address(this)), SUPPLY - requested);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InvalidRecipientPreservesUsableAllowance(uint256 grant, uint256 amount, bool infinite) public {
        grant = bound(grant, 0, SUPPLY);
        amount = bound(amount, 0, grant);
        uint256 allowed = infinite ? type(uint256).max : grant;
        token.approve(spender, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), allowed);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), infinite ? type(uint256).max : grant - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferSpendsOnlyAllowance(uint256 held, uint256 amount, uint256 grant) public {
        held = bound(held, 1, SUPPLY);
        amount = bound(amount, 1, held);
        grant = bound(grant, amount, type(uint256).max);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(spender, grant);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, amount));
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(alice, spender), grant == type(uint256).max ? grant : grant - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersMatchOneTransfer(uint256 amount, uint256 firstPart) public {
        amount = bound(amount, 0, SUPPLY);
        firstPart = bound(firstPart, 0, amount);
        PrismRiot splitToken = new PrismRiot();
        assertTrue(token.transfer(alice, amount));
        assertTrue(splitToken.transfer(alice, firstPart));
        assertTrue(splitToken.transfer(alice, amount - firstPart));
        assertEq(token.balanceOf(alice), amount);
        assertEq(splitToken.balanceOf(alice), token.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(splitToken.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(splitToken.totalSupply(), SUPPLY);
    }

    function testFuzz_RoundTripRestoresBalancesAndPreservesApproval(uint256 amount, uint256 grant) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.approve(spender, grant));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.allowance(alice, spender), grant);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
