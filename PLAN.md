# Exploration: a determinism test layer for consensus-visible output

Scratch plan. Not for commit as-is — the outcome should be an issue, and possibly a
small test package.

## Why

Four recorded instances of the same class, all found after the fact, each fixed with
a bespoke test:

| instance | subsystem | fix |
|---|---|---|
`TestInitOrderDeterminism` | preprocess: var init order | sort dependency sets |
`TestCircDepDeterminism` | preprocess: circular-dep error text | sort the DFS |
#5183 (closed) | `string` → `[]rune` capacity | — |
#5826 | type-expansion gas charge | sort declaration names |

Nothing hunts the class. There is exactly one apphash pin in the tree
(`gno.land/pkg/sdk/vm/apphash_crossrealm38_test.go`) and it covers one scenario.

## What "consensus-visible" means here

Enumerate first, because the suite is only as good as this list:

- **gas consumed** per tx (`ResponseDeliverTx.GasUsed`)
- **error text** — `ABCIResult.Error` is hashed into `LastResultsHash`
- **the save set** → iavl writes → **apphash** (`ResponseCommit.Data`)
- events, if they reach the block

## Layer 1 — repetition in one process

Cheap, and it would have caught **all four** instances above.

- A shared harness: `assertDeterministic(t, n, func() any)` asserting one distinct
  result over n runs. Three places now hand-roll this loop
  (`preprocess_test.go` twice, `typecheck_cost_test.go` once).
- **The corpus must include malformed input.** This is the non-obvious part and the
  reason #5826 survived: the order-sensitive branches sit behind rejection, and
  nothing valid contains an invalid recursive type. A sweep over `examples/` is
  silent on the entire class.

## Layer 2 — several app instances, and NOT via consensus

### What does not work

`randConsensusNet(nValidators, …, appFunc func() abci.Application, …)` in
`tm2/pkg/bft/consensus/common_test.go` looks like the obvious host. It is not
usable:

- it lives in a `_test.go`, unexported, so nothing can import it;
- it is in **tm2**, which cannot import the gno app — dependency direction is
  gno.land → tm2;
- it is only ever driven with `kvstore`/`counter` mocks.

So multi-validator infrastructure exists but is structurally unavailable for VM
determinism. Do not plan around it.

### What does work

Consensus rounds are irrelevant to determinism. What is needed is N **independent
app instances** given identical input, and a comparison of the outputs above.
`gno.land/pkg/gnoland` already supports this in-process:

```go
app, err := NewAppWithOptions(TestAppOptions(memdb.NewMemDB()))
bapp := app.(*sdk.BaseApp)
bapp.InitChain(abci.RequestInitChain{…})
bapp.DeliverTx(abci.RequestDeliverTx{Tx: amino.MustMarshal(tx)})
cres := bapp.Commit()      // cres.Data is the apphash
```

`LoadStdlibCached` exists precisely so repeated app construction is affordable,
which is a good sign this is a supported shape.

### Two test shapes, only the second earns the layer

**2a. Replicas** — N apps, identical genesis, identical txs → identical apphash and
gas. Honest assessment: this adds little over layer 1, since in-process map order is
already covered by repetition. Include it as the skeleton, not the point.

**2b. Divergent history, same final state.** This is what repetition
*structurally cannot* do: every repetition in one process shares the same caches, so
anything that depends on node-local state reports as deterministic.

Vary the path, hold the final transaction identical, and require identical gas and
apphash:

- different **block boundaries** — same txs, split across blocks differently;
- **restart** — commit, discard the app object, rebuild from the same DB, continue;
- **cache warmth** — reach the same state having touched a different set of
  packages first.

Why this matters concretely: this PR (#5826) declined an alternative that would
have priced stdlib from the already-cached `*types.Package` in `permCache`,
specifically because it would make a consensus-visible charge a function of cache
state. That hazard is real, was avoided by judgement, and **no test in the tree
would have caught it**. 2b is that test.

## Findings from the probe (zzz_determinism_probe_test.go, throwaway)

**Q1 — is apphash reproducible across two independently built apps? YES.**
Identical genesis + identical tx gives byte-identical `ResponseCommit.Data` and
identical `GasUsed`. So layer 2 is viable at all.

**Q3 — does the result depend on node-local state? NO, and the useful assertion is
narrower than "divergent history".**

	scenario                                  gas         apphash
	cold (no warm-up)                     2,217,463      A77BC94B…
	warm (2 packages deployed first)      2,280,882      D1B37B9E…
	restarted (same, app rebuilt from DB) 2,280,882      D1B37B9E…   <-- equals warm

The load-bearing line is **warm == restarted**. Throwing the app away and rebuilding
it from the same DB — discarding every in-memory cache — reprices the next tx
identically. That is exactly the `permCache` class of hazard, and it does not
reproduce today. Good news, and now measurable.

cold != warm is **correct, not a finding**: two extra packages in the store means a
bigger IAVL tree, so store gas legitimately differs. Different history is different
state.

So layer 2 collapses to one assertion worth writing: **restart invariance.** Commit
some blocks, rebuild the app from the DB, and the next tx must price exactly as it
would on a node that never restarted. Note that varying *block boundaries* is NOT a
same-state-different-path variation — block height enters the context, so the states
genuinely differ and the comparison is meaningless.

### Harness pitfalls, for whoever implements this

Each cost me a run:

- `Commit()` clears `deliverState`; every block after the first needs its own
  `BeginBlock`, or the next `DeliverTx` nil-derefs in `getContextForTx`
  (`baseapp.go:669`).
- `Signatures: []std.Signature{{}}` (as `app_test.go` uses) only works for a tx
  delivered in InitChain's genesis context. A tx in a real block is verified, so it
  needs a real signature — and an account's *second* tx fails "invalid pubkey"
  because the empty signature pinned an empty pubkey on the first.
- A MemPackage's declared `package` name must match the last path element, and its
  files must be sorted, or you get "invalid package path" / "has unsorted files"
  rather than anything about determinism.

## Open questions to resolve while exploring

1. ~~Is `ResponseCommit.Data` stable across two freshly built apps?~~ **Yes.**
2. **Cost:** ~0.1–0.6s per app instance in these probes, so a handful of instances
   is affordable in a normal test. No build tag needed at this size.
3. ~~Does anything read node-local state on the consensus path today?~~ **Not that
   this reaches.** Restart invariance holds, so `permCache` being `maps.Clone`d per
   tx is doing its job.
4. Where should this live? `gno.land/pkg/gnoland` has the app builder, so the
   restart-invariance test belongs there. The malformed corpus for layer 1 is a
   gnovm concern. Two packages.
5. New: does restart invariance hold across a *pruned* store, or with a different
   `PruneStrategy`? `AppOptions` exposes it and the probe did not vary it.

## Deliverable

An issue with: the four recorded instances, the layer-1/layer-2 split, the
"malformed corpus" insight, the explicit note that tm2's multi-validator harness is
unavailable and why, and whatever question 1 and 3 turn up. Plus a prototype of 2b
if it is small enough to be convincing.
