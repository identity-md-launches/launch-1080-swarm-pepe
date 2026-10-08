The existing token and launch tests are preserved. The added suites require no downloaded dependencies, RPC, environment changes, or edits to the implementation or Foundry configuration.

- `SPEPEAllowanceEdges.t.sol` checks failed-spend rollback for finite and infinite approvals, replacement and revocation of infinite approvals, the finite `uint256.max - 1` boundary, competing spenders, truncated calldata, noncanonical address encoding, zero recipients, and rejection of ETH by every entry point. Each fuzz property runs 1,000 cases using inline configuration.
- `SPEPELedger.invariant.t.sol` maintains expected balances and allowances independently of token reads. It checks every tracked balance and every holder/spender pair, as well as fixed supply, after random transfers, approvals, delegated spends, and forbidden administrative calls. Valid operations and intentional failures are mixed in 256 sequences of 64 calls; unexpected handler reverts fail the test. Actors include the actual deployer and the specified mainnet PoolManager address. The token itself is included as a passive recipient, and zero-address operations are rejected.

To keep generated artifacts in disposable scratch space, the local verification commands are:

```sh
forge build --out test/scratch/out --cache-path test/scratch/cache
forge test --out test/scratch/out --cache-path test/scratch/cache
```

All test dependencies are ordinary repository files outside `test/scratch/`. The scratch directory can be removed before a fresh offline build; the suite also works with the verifier's default `forge test` command.

The launch-flow suite exercises exact ERC-20 transfers at the factory, distributor, and PoolManager boundaries. These local actor tests do not execute Uniswap v4 liquidity accounting, real swaps, launch price derivation, or Merkle proof verification. Those remain integration checks for the launch infrastructure and the supplied protected harness. No live mainnet fork was run; a deployed-factory/PoolManager integration run is still owed before launch. The token makes no external protocol calls itself.

No implementation defect was reproduced during this test expansion.
