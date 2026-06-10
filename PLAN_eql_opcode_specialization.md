# Plan: opcode specialization for ==/!= interface comparisons

Branch: `perf/maxwell/eql_opcode_specialization`, off
`fix/maxwell/runtime_cmp_check` @ `8cd8ec259` (NOT master — this builds on the
cmp PR's `isInterfaceCmp`/`hasInterfaceStaticType`; on master `doOpEql` has no
interface check at all). Worktree: `../gno-eql-opcode`.

## Why

The cmp PR added a per-comparison interface check to `doOpEql`/`doOpNeq`:
`bx := m.PopExpr().(*BinaryExpr)` then `isEql(m, lv, rv, isInterfaceCmp(bx))`.
Reviewer measured ~2.4% overhead on `BenchmarkOpEql_Int` vs master (interleaved
A/B, p=0.002), attributed to the `.(*BinaryExpr)` assertion + threading the
extra `isEql` param — NOT the attribute lookups (gating those recovered nothing).

Node-caching the `isInterfaceCmp` verdict on the BinaryExpr does NOT help: the
hot path would still need the assertion to read it. Only moving the decision
OUT of the hot path removes the cost.

## What the prototype does (already applied, uncommitted-then-WIP-committed)

Decide interface-ness at instruction selection, not execution:
- `machine.go`: add `OpEqlIface Op = 0x39`, `OpNeqIface Op = 0x3A`; Run-loop
  cases dispatch to `doOpEqlIface`/`doOpNeqIface` (both `m.incrCPU(OpCPUEql/Neq)`).
- `op_eval.go` (`*BinaryExpr` eval dispatch): `x` is already a typed
  `*BinaryExpr` here (no assertion), so for `EQL`/`NEQ` call `isInterfaceCmp(x)`
  and push the `*Iface` op when true, plain `OpEql`/`OpNeq` otherwise.
- `op_binary.go`: `doOpEql`/`doOpNeq` revert to master shape — `m.PopExpr()`
  (no assertion), `isEql(m, lv, rv, false)`. New `doOpEqlIface`/`doOpNeqIface`
  do the same with `true` (the uncomparable-dynamic-type panic path).

## Result (BenchmarkOpEql_Int, Apple M3, n=10, benchstat)

- isolated op (`sec/op(pure)`, the changed code): 54.74n → 42.54n = **-22.3%,
  p=0.000**. More than recovers the 2.4%.
- total `sec/op`: flat (p=0.123) — bench harness push/reset setup dominates wall.
- `-run Files -test.short`: passes. Uncomparable-iface filetests still panic.

Baseline/after raw numbers saved at /tmp/bench_head.txt and /tmp/bench_proto.txt
on the original machine (regenerate if gone: bench HEAD of cmp branch vs this).

## TODO to make it PR-ready

1. **Stringer regen (REQUIRED).** `string_methods.go` was NOT updated; `Op.String()`
   on 0x39/0x3A will misindex. Regenerate the Op stringer (it's `stringer`-generated;
   find the `//go:generate` directive). Verify no panic.
2. **Audit exhaustive Op switches / tables** for the two new ops: gas/CPU tables
   (`OpCPUEql` etc.), any `switch op` over binary ops, debug/printers, the
   transcript/replay machinery. grep `OpNeq` / `OpBandn` to find the set of
   places that enumerate ops.
3. **Tests:** add a filetest or unit test asserting interface `==`/`!=` routes to
   the Iface op and still panics on uncomparable dynamic types (the cmp PR's
   `cmp_uncomp_*` filetests already cover behavior; consider a direct op-selection
   assertion). Confirm `switch`-tag path (op_exec.go ~985, uses
   `hasInterfaceStaticType`) is unaffected — it does NOT go through doOpEql.
4. **Verification gate (project CLAUDE.md):**
   - `go test ./gno.land/pkg/sdk/vm/ -run Gas`
   - `go test ./gno.land/pkg/integration/ -run TestTestdata`
   - `go test ./gnovm/pkg/gnolang/ -run Files -test.short`
   - run `/simplify`.
5. **Re-benchmark** with the final code (after stringer) to confirm the -22% holds.
6. Decide: separate follow-up PR (recommended — it's a perf refinement on top of
   the cmp fix) vs folding into the cmp PR.

## Notes
- Constant `false` arg to `isEql` remains in the common path (cheap). Removing it
  fully would need a separate non-iface `isEql`; almost certainly not worth it.
- `isInterfaceCmp(x)` now runs at eval-push time (same lookups, relocated).
  Could precompute at preprocess if ever shown to matter — reviewer says it
  doesn't.
- Op values 0x39/0x3A were free gaps between `OpBandn` (0x38) and `OpEval` (0x40).
