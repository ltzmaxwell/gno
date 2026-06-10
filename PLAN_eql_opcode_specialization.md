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

## OPEN DESIGN QUESTION — is two new opcodes the right design? (resume here)

Concern: adding `OpEqlIface`/`OpNeqIface` alongside the general `OpEql`/`OpNeq`
doubles the op surface for `==`/`!=` to win 2.4% on the cheapest op. The variants
aren't a new *concept*, just a static perf flag promoted to an opcode — a
special-case smell. Every exhaustive `switch op` (gas tables, stringer, debug,
replay) must now know 4 ops where 2 suffice.

Counter: opcode specialization is an established LOCAL pattern — `OpBinary1`
already exists as a separate op for the LAND/LOR short-circuit instead of
branching inside a general op. And the iface-vs-not split is genuinely static
(known at preprocess), so encoding it in the instruction is defensible.

### Alternative considered: node-cache instead of new opcodes
Keep the idiomatic `bx := m.PopExpr().(*BinaryExpr)` assertion (cf. doOpBinary1),
precompute the iface verdict at preprocess, read it in doOpEql:
`isEql(m, lv, rv, bx.isIfaceCmp)`. Keeps the op set minimal; data-driven, not
control-flow-driven.

BUT two doubts, UNMEASURED:
1. The prototype's -22% likely came from removing the ASSERTION (+ call frames),
   NOT the lookups — reviewer showed gating the lookups recovered nothing. Node-
   cache KEEPS the assertion, so it may recover little and stay near the PR's
   current cost rather than reaching master.
2. Storage cost can erase the gain:
   - attribute (map): per-eval `GetAttribute` is a map lookup — same cost class
     as the `hasInterfaceStaticType` lookups being removed → ~net zero.
   - struct field on BinaryExpr: avoids the map but touches the AST node layout
     and its amino (de)serialization — own surface/risk.

### Decision plan (do this before polishing the opcode version)
Prototype the node-cache variant (struct-field form) and benchstat ALL THREE:
master vs node-cache vs opcode. ~10 min.
- If node-cache recovers most of the 22% → prefer it (no op-set bloat).
- If it stalls at the assertion cost → the real question becomes "is 2.4% on the
  cheapest op worth ANY of this?" Full-program sec/op was flat (p=0.123), so the
  honest answer may be "no — drop the optimization entirely." Don't ship op-set
  expansion for a microbench-only win.

## Notes
- Constant `false` arg to `isEql` remains in the common path (cheap). Removing it
  fully would need a separate non-iface `isEql`; almost certainly not worth it.
- `isInterfaceCmp(x)` now runs at eval-push time (same lookups, relocated).
  Could precompute at preprocess if ever shown to matter — reviewer says it
  doesn't.
- Op values 0x39/0x3A were free gaps between `OpBandn` (0x38) and `OpEval` (0x40).
