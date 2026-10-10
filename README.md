# Prism Riot (PRIO)

A fixed supply ERC-20 for the IdentityMD custom token launch. The sole production
contract is [`PrismRiot`](src/PrismRiot.sol), built on the vendored OpenZeppelin
Contracts v5.0.2 ERC-20 implementation.

| Deployment parameter | Value |
| --- | --- |
| Solidity artifact | `src/PrismRiot.sol:PrismRiot` |
| Solidity contract name | `PrismRiot` |
| Token name / symbol | `Prism Riot` / `PRIO` |
| Decimals | `18` |
| Whole token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10**27`) |
| Constructor arguments | None (`[]`) |
| Deployment ETH value | `0` |
| Initial recipient | Constructor `msg.sender`, the immediate deployer |
| Launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM / optimizer | Cancun / enabled, 200 runs |
| Bytecode metadata hash | `none` |

The constructor mints the entire supply once and emits the standard mint
`Transfer` event. If a factory creates the token, the factory receives all tokens;
the transaction origin and the caller of the factory receive none automatically.
There are no constructor calls to other contracts, address parameters, linked
libraries, initialization steps, or external services to configure.

## Behavior and assumptions

The brief specifies a custom name, symbol, and fixed supply. Transfer behavior is
therefore standard ERC-20: exact amounts move, with no taxes, fees, reflections,
rebasing, transfer limits, or account exemptions. Zero value transfers and
self-transfers are valid and emit `Transfer`. Transfers to the zero address revert,
including zero value transfers.

`approve` sets an allowance, replacing any previous value, and emits `Approval`.
`transferFrom` spends the caller's allowance and checks the holder's balance;
failed operations revert atomically. An allowance of `type(uint256).max` has the
standard OpenZeppelin unlimited behavior and is not decremented. Allowance spending
does not emit `Approval` in this version; integrations should query `allowance`.
Spending still requires allowance when the spender is also the holder.

There is no owner, mint endpoint, burn endpoint, pause, blacklist, seizure,
upgrade, proxy, permit, or administrative balance control. Total supply remains
constant after construction. ERC-20 transfers make no receiver callbacks or other
external calls. The contract has no payable entry point or asset recovery method;
tokens sent to the token contract itself cannot be recovered.

## Build and check

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies are ordinary vendored files under `lib/`, with their
licenses. No package installation, submodules, RPC, fork, wallet, environment
variables, FFI, or filesystem permissions are required to build or test.
[`DEPENDENCIES.json`](DEPENDENCIES.json) records each upstream release and commit.
OpenZeppelin includes only ERC-20 and its transitive imports; forge-std v1.9.7
includes its source tree for the test framework. Vendored sources are unmodified.

The tests cover metadata, exact constructor supply and mint event, EOA and CREATE2
factory deployment, launch allocation and claim transfer amounts, both directions
of pool token movement, transfer/approval events, allowance replacement and
revocation, finite and unlimited allowances, zero amounts, self-transfers,
insufficient balances/allowances, invalid addresses, atomic failure, and absence
of privileged mint/burn/freeze/upgrade entry points. Runtime checks enforce the
deployment size limit and reject `DELEGATECALL`, `CALLCODE`, and `SELFDESTRUCT`.

Four parameter fuzz tests run 512 cases each. The stateful invariant runs 256
sequences of 64 calls against an independent balance and allowance model for four
actors. It checks exact accounting, conservation of the complete supply, and
atomic rejection of invalid operations after mixed transfers and approvals.
All tests create fresh state and use deterministic local test identities.

The local factory and pool-role test covers ERC-20 movement only. The supplied
protected integration test belongs to the network's separate launch harness and
uses platform contracts and launch environment values absent from this repository.
Actual Uniswap v4 pool initialization, seeding, and swaps remain that harness's
verification responsibility; the local tests do not claim to execute them.

## Deployment and operations

The network deployer should use the `PrismRiot` creation bytecode built with this
configuration and no appended constructor arguments. For review, obtain it with:

```sh
forge inspect src/PrismRiot.sol:PrismRiot bytecode
forge inspect src/PrismRiot.sol:PrismRiot abi
```

The factory must perform the deployment so it holds the full supply before
distribution. Launch allocation is handled by the factory: 10% to the network
distributor, 88% for pool seeding, and the remaining 2% to the launch's specified
recipient. The token contains no allocation addresses or distribution mechanism.
The manifest and launch execution are the network's separate steps; this project
does not create `launch.json` or broadcast transactions.

### After launch

There are no owner settings or configuration transactions. The launch operator
must verify deployed source and compiler settings, confirm the constructor's
single mint of `10**27` units to the factory, and reconcile the factory's subsequent
distribution with the approved launch terms. Pool operation and contributor claims
are the platform's responsibilities. Holders control their tokens and allowances;
integrations must use 18 decimal units and check ERC-20 return values.

Holders should grant only necessary allowances and revoke unused ones. As with
standard ERC-20, replacing a live allowance can race a spender's transaction;
set it to zero and wait for confirmation before setting a new amount when needed.
The deployer has no post-deployment control or recovery powers.

Foundry unit, fuzz, invariant, and formatting checks are the local verification
tools used here. Slither and Mythril have not been run. This implementation and its
tests are not an independent security audit; the network's independent review and
deployment verification remain release responsibilities.

Local validation with Foundry 1.8.5 and Solidity 0.8.26 passed `forge build`,
`forge test` (32 tests, including 2,048 fuzz cases and 16,384 stateful calls), and
`forge fmt --check`. A fresh copy containing only the configuration, sources,
tests, and vendored dependencies also passed `forge test --offline --threads 4`
with an empty environment. The production runtime is 1,752 bytes and the creation
and runtime bytecode have no library link references.
