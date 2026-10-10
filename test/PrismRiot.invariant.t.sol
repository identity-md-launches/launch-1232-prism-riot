// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PrismRiot} from "../src/PrismRiot.sol";

/// @dev All token movements stay within these four actors so the balance sum is exhaustive.
/// The model uses its own balances and allowances, not the token's state, to select valid actions.
contract PrismRiotHandler is Test {
    PrismRiot private immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PrismRiot token_) {
        token = token_;
        actors[0] = makeAddr("actor0");
        actors[1] = makeAddr("actor1");
        actors[2] = makeAddr("actor2");
        actors[3] = makeAddr("actor3");
        expectedBalance[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    // Deliberately reach the infinite-allowance branch instead of relying on random uint256s.
    function approveInfinite(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, type(uint256).max));
        expectedAllowance[owner][spender] = type(uint256).max;
    }

    function transferFullBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    // Make finite allowance exhaustion reachable even when random approvals are much larger
    // than the entire supply. Separate transferFrom calls still exercise existing approvals.
    function approveAndSpend(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(from, spender), amount);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        expectedAllowance[from][spender] = 0;
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferFrom(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 maximum = allowed < expectedBalance[from] ? allowed : expectedBalance[from];
        amount = bound(amount, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % 4];
        address to = actors[toSeed % 4];
        uint256 amount = expectedBalance[from] + 1;
        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertFalse(success, "overspending balance succeeded");
        assertEq(
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount)
        );
    }

    function spendOverAllowance(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 allowed = expectedAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, allowed + 1)));
        assertFalse(success, "overspending allowance succeeded");
        assertEq(
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
    }

    // Approval must survive a later balance failure, including when from == to or spender.
    function transferFromOverBalance(uint256 fromSeed, uint256 spenderSeed, uint256 toSeed, bool infinite) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = actors[toSeed % 4];
        uint256 amount = expectedBalance[from] + 1;
        uint256 allowed = infinite ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, allowed));
        expectedAllowance[from][spender] = allowed;
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        assertFalse(success, "allowance bypassed the balance check");
        assertEq(
            reason,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount)
        );
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.transfer, (address(0), amount)));
        assertFalse(success, "transfer to zero burned tokens");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function transferFromToZero(uint256 fromSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % 4];
        address spender = actors[spenderSeed % 4];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 maximum = allowed < expectedBalance[from] ? allowed : expectedBalance[from];
        amount = bound(amount, 0, maximum);
        vm.prank(spender);
        (bool success, bytes memory reason) =
            address(token).call(abi.encodeCall(token.transferFrom, (from, address(0), amount)));
        assertFalse(success, "delegated transfer to zero burned tokens");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % 4];
        vm.prank(owner);
        (bool success, bytes memory reason) = address(token).call(abi.encodeCall(token.approve, (address(0), amount)));
        assertFalse(success, "approved the zero address");
        assertEq(reason, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
    }
}

/// @dev These settings travel with the tests without changing repository configuration.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PrismRiotInvariantTest is Test {
    PrismRiot private token;
    PrismRiotHandler private handler;

    function setUp() public {
        token = new PrismRiot();
        handler = new PrismRiotHandler(token);
        assertTrue(token.transfer(handler.actors(0), token.totalSupply()));

        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.revoke.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.transferOverBalance.selector;
        selectors[5] = handler.spendOverAllowance.selector;
        selectors[6] = handler.approveInfinite.selector;
        selectors[7] = handler.transferFullBalance.selector;
        selectors[8] = handler.approveAndSpend.selector;
        selectors[9] = handler.transferFromOverBalance.selector;
        selectors[10] = handler.transferToZero.selector;
        selectors[11] = handler.transferFromToZero.selector;
        selectors[12] = handler.approveZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @dev Every holder must still be able to move its full balance after any sequence.
    /// This checks liveness as well as the view-only accounting invariant.
    function afterInvariant() public {
        for (uint256 i = 1; i < 4; ++i) {
            handler.transferFullBalance(i, 0);
            invariant_SupplyBalancesAndAllowancesMatchModel();
        }
        assertEq(token.balanceOf(handler.actors(0)), 1_000_000_000 * 10 ** 18);
        handler.transferFullBalance(0, 1);
        invariant_SupplyBalancesAndAllowancesMatchModel();
        assertEq(token.balanceOf(handler.actors(1)), 1_000_000_000 * 10 ** 18);
    }

    function invariant_SupplyBalancesAndAllowancesMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "balance diverged from model");
            assertEq(token.allowance(actor, address(0)), 0, "zero spender acquired an allowance");
            sum += token.balanceOf(actor);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(actor, spender),
                    handler.expectedAllowance(actor, spender),
                    "allowance diverged from model"
                );
            }
        }
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
        assertEq(sum, token.totalSupply());
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.name(), "Prism Riot");
        assertEq(token.symbol(), "PRIO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
    }
}
