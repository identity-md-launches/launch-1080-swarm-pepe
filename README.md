# Swarm Pepe (SPEPE)

`src/SPEPEToken.sol:SPEPEToken` is a plain ERC-20 with a fixed supply of
1,000,000,000 SPEPE and 18 decimals (`1000000000000000000000000000` minor units).
Its argument-free constructor credits **all** units to `msg.sender` and emits
one mint `Transfer` event. When deployed by the launch factory, the factory holds
the whole supply. There are no subsequent mint or burn functions.

The name, symbol, decimals and total supply are constants. Only balances and
allowances change. There is no owner, administrator, initialization, proxy,
upgrade path, fee, tax, transfer limit, pause, blacklist or privileged balance
access. The token makes no external calls and uses no delegation or destruction
opcodes. The factory, distributor and PoolManager have the same ERC-20 rights as
every other holder; none needs an exemption.

## Build and check

With Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins solc **0.8.26**, Cancun, optimization with 200 runs and
`bytecode_hash = "none"`. There are no package dependencies, submodules or
generated sources to fetch. The included test support declares only the
Foundry cheatcodes it uses. Tests require no RPC, environment variables, wallet,
FFI or filesystem permissions. The same commands work offline once the compiler
and Foundry are provisioned.

## ERC-20 behavior

- `transfer` and `transferFrom` return `true` and deliver exactly the amount
  requested, or revert atomically. Insufficient funds, insufficient allowance
  and zero sender/recipient addresses revert with typed errors.
- Zero-value transfers between valid addresses succeed and emit `Transfer`.
  Self-transfers preserve balances and still require sufficient balance.
- `approve` replaces an allowance and emits `Approval`; setting it to zero
  revokes it. Zero approvers/spenders are rejected. A finite allowance is reduced
  by `transferFrom`, including a delegated self-transfer; maximum `uint256`
  denotes unlimited approval and is preserved. Allowance spending emits only
  `Transfer`. Calling `transferFrom` on one's own balance still needs allowance.
- Holders should account for the usual ERC-20 allowance replacement race when
  changing an active approval (revoke and confirm before granting a new amount).
- Sending to the specified nonzero remainder address is an ordinary transfer;
  it does not reduce `totalSupply`. There is no asset recovery function or native
  ETH receiver. Accidental transfers to inaccessible addresses cannot be undone.

## Deployment parameters

`launch.json` supplies the custom-token launch manifest. Its root keys are
`kind`, `token`, `contracts`, `pool`, `economics` and `notes`. Chain information
is documented here and in `notes`; **there is no root `chainId` field**.
The manifest names `SPEPEToken`, provides no constructor arguments and lists no
application contracts.

| Parameter | Fixed value |
| --- | --- |
| Network | Ethereum mainnet, chain ID 1 |
| Uniswap v4 PoolManager | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| Paired currency (IMD) | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee | `3000` (0.3%, charged by the pool) |
| Tick spacing | `60` |
| Provenance initial sqrtPriceX96 | `125270724187523965593206900` |
| `economics.poolBps` | `9000` of the whole supply |
| `economics.initialMarketCapWei` | `2500000000000000000000` paired-currency minor units (2500 IMD) |
| `economics.remainderTo` | `0x000000000000000000000000000000000000dead` |

These addresses and economic inputs come directly from the assignment. The
remainder address is explicitly requested, not a substitute for an unknown
recipient. Mainnet selection is the deployment system's responsibility; the
token itself is an ordinary chain-independent ERC-20.

The provenance price describes the square root of the paired-minor-unit / SPEPE-
minor-unit ratio scaled by 2^96, with SPEPE as currency0. The launch system must
derive the actual opening price from the economic inputs using the deployed
currency ordering. It must not blindly reuse the provenance value when SPEPE is
currency1. The paired units are IMD minor units, not ETH wei.

## Launch and operational responsibilities

The network launches the artifact through `ProjectFactory.launchCustom`. The
factory creates the token, then sends 10% (100,000,000 SPEPE, `1e26` units) to its
Merkle distributor, seeds the pool from its own remaining balance with up to 90%
(900,000,000 SPEPE, `9e26` units), and forwards the remainder to `remainderTo`.
With the full pool allocation used there is no remaining balance; liquidity
rounding can leave units for the remainder recipient. The factory and
distributor implement the swarm allocation and claims. This token implements
only the initial mint and ordinary ERC-20 operations.

The launch operator supplies the factory, launch identifier, distributor and
liquidity configuration through the network infrastructure. None is a token
constructor parameter or a configurable token setting. The operator must verify
mainnet, the paired asset, the deployed artifact and currency ordering, execute
the launch and verify the resulting supply, allocations and pool. Traders and
routers handle approvals and swap slippage. Pool initialization, liquidity
accounting and Merkle proofs belong to their respective external contracts.

After launch, there are no settings, keys, maintenance calls or ownership to
hand over for this token. No transactions are broadcast by this project.

## Validation coverage and limits

The suite covers construction through CREATE2, metadata and full factory
ownership, mint/transfer/approval events, lossless transfers, zero amounts,
self-transfers, full-supply moves, allowances and revocation, unlimited approval,
failure rollback, unauthorized spending, missing administrative selectors,
native-value rejection and a runtime opcode scan. Three fuzz properties use
1,000 cases each. A stateful invariant uses 256 sequences of 64 actions mixing
transfers, approvals, delegated transfers and failed overspending to check fixed
supply and conservation across all participating balances.

The offline launch tests simulate token movements for allocation, claims,
liquidity seeding, buys and sells using the supplied PoolManager address. They
also cover an approved router and rounding remainder. They do not execute
Uniswap v4 pool logic or validate Merkle proofs. The pinned protected test uses
the network's factory/liquidity harness and real v4 implementation; that
independent harness and its deployment inputs are not included here. Its
integration run remains the launch system's responsibility. No mainnet fork,
Slither, Mythril or independent security audit is claimed by the local suite.
