# Opcode specialization for interface `==`/`!=` (OpEqlIface/OpNeqIface)

## Status

Implemented on `perf/maxwell/eql_opcode_specialization`. Follow-up to #5713
(runtime panic on comparing uncomparable types via interface).

## Context

PR #5713 made `doOpEql`/`doOpNeq` decide per comparison whether the operands
are statically interface-typed: `bx := m.PopExpr().(*BinaryExpr)` followed by
`isEql(m, lv, rv, isInterfaceCmp(bx))`. The reviewer measured the cost on
`BenchmarkOpEql_Int` vs master (interleaved A/B): ~2.4% total, +22% on the
isolated op (`sec/op(pure)`), attributed to the type assertion and the
threaded parameter — not to the attribute lookups inside `isInterfaceCmp`.

The static verdict cannot be replaced by a runtime check. Counterexample
(verified against Go):

```go
var s []int
s == nil           // true — legal, no panic
any(s) == any(s)   // panic: comparing uncomparable type []int
```

Both comparisons reach `isEql` with the byte-identical operand pair
`{T: []int, V: nil}` (the `s == nil` nil is converted to the slice type).
Same runtime values, different required behavior — so the interface-ness
verdict must travel from the preprocessor to the comparison through some
static carrier.

## Decision

Carry the verdict in the instruction. Two new opcodes, `OpEqlIface` (0x39)
and `OpNeqIface` (0x3A), are selected in `doOpEval`'s `*BinaryExpr` case —
where the expression is already concretely typed, so no assertion is needed —
whenever `isInterfaceCmp(x)` holds for `==`/`!=`. The plain `doOpEql`/`doOpNeq`
revert to master shape (`m.PopExpr()`, constant `false` to `isEql`); the
`*Iface` handlers pass `true`, enabling the uncomparable-dynamic-type panic.
Gas reuses `OpCPUEql`/`OpCPUNeq`. Precedent: `OpBinary1` already exists as a
separate op solely for LAND/LOR short-circuit dispatch.

## Alternatives considered (all measured)

`BenchmarkOpEql_Int` `sec/op(pure)`, interleaved n=10, Apple M3, identical
bench file across all refs:

| carrier | ns/op | vs master |
|---|---|---|
| master (no check) | 44.34 | baseline |
| #5713: assertion + `isInterfaceCmp` per comparison | 54.08 | +22.0% (p=0.000) |
| node attribute (`GetAttribute(ATTR_IFACE_CMP)`) | 52.16 | +17.6% (p=0.000) |
| opcode (this ADR) | 43.02 | flat (p=0.123) |

- **Node attribute**: `GetAttribute` is on the `Expr` interface, so it avoids
  the assertion — but the dynamic method dispatch plus string-keyed map lookup
  costs the same class as what it replaces, and the bench is its best case
  (nil attribute map). Attributes are also not persisted.
- **Struct field on BinaryExpr**: an unexported field doesn't survive node
  persistence; an exported one changes amino encoding of a core AST node.
  Disproportionate for this win.
- **Drop the optimization**: total `sec/op` is flat in all variants (the
  regression is isolated-op only), but the cost was reviewer-flagged and the
  recovery is small and contained.

## Consequences

- The `==`/`!=` op surface doubles (2 → 4). Ops are enumerated in exactly four
  places repo-wide: the `Op` const block, the run-loop switch, `word2BinaryOp`
  (untouched — selection happens after it, in `doOpEval`), and the generated
  stringer (regenerated). Nothing outside `pkg/gnolang`.
- The handler bodies repeat the file's existing pop/peek/set idiom
  (cf. `doOpLss`/`doOpLeq`/`doOpGtr`/`doOpGeq`); factoring them into a shared
  parameterized helper would reintroduce the branch this change removes.
- `doOpEqlIface` has no bigint gas branch: bigints exist only during
  preprocess const-eval, where operands are never interface-typed.
- The `switch`-tag comparison path (`op_exec.go`) computes its own verdict and
  calls `isEql` directly; it is unaffected.

## Verification

- `TestOpEvalSelectsIfaceCmpOps` asserts op selection (iface/concrete × EQL/NEQ,
  LSS unaffected); the 20 `tests/files/types/cmp_uncomp_*` filetests cover the
  panic behavior.
- Gas, txtar (`TestTestdata`), and `Files -short` suites green.
- Final bench vs master: 43.38n vs 45.01n `sec/op(pure)`, p=0.218 —
  statistically indistinguishable; the #5713 isolated-op regression is fully
  recovered.
