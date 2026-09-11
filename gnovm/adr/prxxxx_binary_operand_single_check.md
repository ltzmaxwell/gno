# Binary operands are checked once, by the branch that converts them

## Context

Interface-satisfaction walks in the preprocessor are metered since #6164.
For a binary expression the preprocessor ran that walk twice per typed
operand: `BinaryExpr.AssertCompatible` asserted assignability up front, then
the operand branch called `checkOrConvertType`, which asserts it again before
converting. `S{} == i` cost 97K gas per statement against 49K for `var x I =
S{}`; `append(s, S{})` had the same shape through `specifyType` plus the
argument loop. A per-form gas audit (`TestPreprocess_IfaceImpl_OneWalkPerForm`)
found no other doubled form.

A first cut deleted the branch call. That dropped the conversion the branch
also performed, wrapping an unnamed operand in its named counterpart, so
`P{1} == struct{X int}{1}` evaluated false at runtime (`isEql` compares
dynamic types first). No filetest covered it.

## Decision

Split the two responsibilities instead of patching one branch:

- `AssertCompatible(lt, rt)` checks only operator well-formedness: the
  operator is defined on the operand type, and for `==`/`!=` the type is
  comparable (slice, func, map only against nil). It no longer takes a store.
- Every operand branch converts exactly one operand through
  `checkOrConvertType`, which is the single assignability check. Two branches
  that relied on `AssertCompatible` alone (typed constant against typed
  variable, either side) now call it too. `checkOrConvertOperands` names the
  shared specificity rule; `checkOperands` is the check-only form for an
  interface-typed constant; `convertUntypedOperands` checks two untyped
  operands as written before either takes its default type.
- `mustAssignableTo` formats a failed binary operand in the text
  `AssertCompatible` used to emit, so the 63 goldens pinning
  `invalid operation: ... (mismatched types X and Y)` are unchanged.
- The constant-zero-divisor check moves after operand conversion, so a type
  mismatch is reported before division by zero, as in Go.
- `specifyType` no longer asserts assignability while binding generic
  arguments; the argument loop checks each one right after.
- `checkOrConvertType` itself is one linear pass: constant, shift, then a
  single static-type lookup and check, after which a typed operand gets only
  the named-type wrap and an untyped one the push-down or conversion. The
  old tail call into `convertType` re-derived those facts, and the unary
  branch repeated the check above it. `convertType` stays for its three
  check-free callers.
- Every operator form asserts "operator defined on type" through one
  `assertOperatorDefined`; six sites carried their own copy.

## Alternatives considered

- Call `convertType` directly in the both-typed branch. Minimal and correct,
  but leaves the check in two places and reads as an exception.
- Cache satisfaction results per type pair. Hides real work from the meter
  across statements; a per-expression cache adds state and invalidation for
  a redundancy that is better removed.
- Remove the check from `checkOrConvertType`. It is the only check at its
  51 other call sites.

## Consequences

- One walk per interface destination for every form, pinned by the per-form
  test; two-destination forms cost exactly two.
- `eql_named_unnamed.gno` pins named-vs-unnamed equality for struct, array
  and pointer.
- `add_b2.gno` re-pinned: `1 + "a"` now reports
  `invalid operation: ... (mismatched types <untyped> bigint and <untyped>
  string)` like its siblings, instead of `cannot use untyped Bigint as
  StringKind`.
- A typed constant compared with a typed variable of an assignable but
  distinct type is now converted before comparison rather than compared by
  dynamic type at runtime.
