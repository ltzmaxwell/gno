# PR — interrealm v3a Phase A starter + Phase B migrations (stacked on PR #5669)

Stacked commits on top of `pr-5669` (v2's Phase 3 PR) that begin v3a's
Phase A (machine-op identity model, generalized anchor, reference
implementations) and Phase B (real /p/ library migrations).

This ADR ties the commits together and documents what's intentionally
deferred. It satisfies AGENTS.md's "every non-trivial AI-assisted PR
must include an ADR" requirement.

## Context

PR #5669 (v2 Phase 3) closes:
- Type-pun launder (Attack G).
- Primitive-receiver cross-pkg attack (Attack H, narrow patch in
  commit 9d560263d).
- Unreal-HIV cross-realm write false-positives.

What v2 leaves open:
- **omarsy class**: the uverse `realm` interface is implementable by
  user types, allowing forged identity values to be passed where
  `cur realm` / `rlm realm` parameters are expected.
- **Same-pkg variant of Attack H**: v2's narrow patch fires only when
  the primitive receiver's pkg differs from the param's pkg. A
  malicious or compromised `/p/` author can declare both types in the
  same pkg to bypass.

v3a (designed in `gnovm/adr/interrealm_v3a.md`) addresses both via:
- Concrete `runtime.Realm` struct + machine-op identity queries
  (`runtime.Caller()` etc.). No user-passable realm value → no
  forgery surface.
- Generalized anchor: drop the pkg-difference check so the anchor
  fires for any primitive-recv method with a /p/-declared pointer
  param.

## Commits in this stack

1. **`b692555ff` docs(interrealm): v3a/v3b ADRs + discipline + capability-levels exploration**
   - `gnovm/adr/interrealm_v3a.md` — Phase A design (the committed plan).
   - `gnovm/adr/interrealm_v3b.md` — optional type-qualifier extension.
   - `gnovm/adr/interrealm_discipline.md` — library-author rules
     for safe interface contract design.
   - `gnovm/adr/interrealm_capability_levels.md` — exploration of
     stronger language-level options if discipline + marker proves
     insufficient.

2. **`2e5a01ec3` fix(interrealm): generalize primitive-recv anchor to same-pkg /p/ types**
   - Drop the `pdt.PkgPath != recvPkgPath` check in the Attack-H
     predicate (renamed `isPrimitiveRecvWithForeignPPtrParam` →
     `isPrimitiveRecvWithPPtrParam`).
   - Anchor fires for any primitive-recv method with a /p/-declared
     pointer param.
   - Outer `pid != m.Realm.ID` check still allows legitimate same-realm
     intra-pkg patterns.
   - New regression filetest `zrealm_launder_h2_samepkg.gno` plus
     `SamePkgEvil` fixture in `/p/launderpkg`.

3. **`5905c79c5` feat(interrealm): add runtime.{Caller,Self,Origin} as v3a identity-query API**
   - `runtime.Caller()` = alias for `PreviousRealm()` (one realm
     transition up).
   - `runtime.Self()` = alias for `CurrentRealm()`.
   - `runtime.Origin()` = `Realm{addr: OriginCaller, pkgPath: ""}`.
   - Returns concrete `runtime.Realm` struct (already non-implementable
     by user types — that's the omarsy closure for any code adopting
     the new API).
   - Filetest `zrealm_runtime_caller_filetest.gno` verifies identity
     equivalences.

4. **`e5f80ec8e` test(interrealm): canary /p/ ACL helper using runtime.Caller (omarsy-free pattern)**
   - New `/p/demo/tests/v3aclhelper` package with `CheckCaller`,
     `CallerPath`, `CallerIsUser` helpers using `runtime.Caller()`.
   - Demonstrates the v3a /p/-helper pattern: no `_ int, rlm realm`
     parameter shape, identity sourced from the VM.
   - Filetest exercises it from /r/ and verifies caller identity
     resolves correctly.

5. **`b1a114ab8` test(interrealm): canary /r/ realm demonstrating v3a Ownable pattern end-to-end**
   - New `/r/tests/vm/v3acanary` realm with full Ownable-style state:
     `Init`, `Owner`, `TransferOwnership`, `DropOwnership`.
   - All ACL via `runtime.Caller()`, no realm-typed parameters.
   - Filetest exercises bootstrap → authorized transfer → ACL
     rejection after ownership changes hands (uses `revive()` for
     cross-realm abort catching, per v2 Phase 3 semantics).

6. **`b4fb9424e` feat(ownable/v1): v3a-aligned ownable using runtime.Caller (coexists with v0)**
   - New `/p/nt/ownable/v1` package — successor to v0.
   - `Ownable` struct, `NewWithAddress`, `NewWithCaller` (new
     constructor capturing `runtime.Caller()` at init), `OwnedBy`,
     `AssertOwnedBy`, `TransferOwnership`, `DropOwnership`, `Owner`.
   - No `_ int, rlm realm` parameter shape.
   - Unit tests cover pure-data API; mutating-method coverage falls to
     the canary filetest (see "Open issues" below).
   - `doc.gno` documents v1 vs v0 trade-offs.

7. **`042a7af99` docs(interrealm): PR-level ADR for v3a Phase A starter stack**
   - This document (initial version).

8. **`7496f4897` refactor(loci): migrate to v3a runtime.Caller pattern (Phase B)**
   - In-place migration of `/p/n2p5/loci.Set` from
     `(_ int, rlm realm, value)` shape to plain `(value)` signature
     using `runtime.Caller().Address()`.
   - Updates `/r/n2p5/loci` caller and the package's own test/filetest.
   - First real Phase B migration — demonstrates the playbook on a
     small self-contained library.

9. **`9e18dd151` refactor(microblog): migrate to v3a runtime.Caller pattern (Phase B)**
   - `/p/demo/microblog.NewPost` migrated to plain signature using
     `runtime.Caller().Address()` for author identity.
   - `/r/demo/microblog` caller updated.
   - Test uses `cross()` scaffolding (documented as transitional).

10. **`e524c2a61` refactor(subscription): migrate lifetime+recurring UpdateAmount to runtime.Caller**
    - `/p/demo/subscription/lifetime.UpdateAmount` and
      `/p/demo/subscription/recurring.UpdateAmount` both migrated.
    - Now satisfy the existing `Subscription` interface (which already
      had the v3a-style signature).

## What this delivers

| Property | Before | After |
|---|---|---|
| omarsy attack via forged `rlm realm` value | open | **closed** for any code using `runtime.Caller()` |
| Same-pkg variant of Attack H | open | **closed structurally** (anchor fires uniformly) |
| Cross-pkg Attack H | closed by 9d560263d | unchanged |
| Identity query in /p/ helpers | requires `rlm realm` parameter (forgeable) | machine op (`runtime.Caller()`) |
| /p/ library with omarsy-free ACL | not available | `/p/nt/ownable/v1` reference impl |
| Realm-level reference impl | not in tree | `/r/tests/vm/v3acanary` reference |
| `/p/n2p5/loci` | v2 `(_ int, rlm, ...)` shape | v3a runtime.Caller |
| `/p/demo/microblog` | v2 shape | v3a runtime.Caller |
| `/p/demo/subscription/{lifetime,recurring}` | v2 shape | v3a runtime.Caller |

## What is intentionally deferred

Per `gnovm/adr/interrealm_v3a.md`, Phase A includes additional work
not in this stack:

- **`OriginRealm` field on `FuncValue`/`BoundMethodValue`** with
  generalized indirect-dispatch borrow (function values, interface
  methods, function fields).
  - Why deferred: this is a runtime behavior change for indirect
    dispatch that could affect existing /p/ helpers relying on
    caller-authority semantics for callbacks. Needs careful test
    coverage before landing.
- **Call-form analyzer at preprocess**: classify each `CallExpr` as
  direct or indirect; emit the appropriate dispatch op.
  - Why deferred: precise classification has edge cases (parenthesized
    identifiers, embedded-method promoted access, generic
    instantiation). Needs explicit spec mirroring Go's
    method-value/method-expression semantics.

Phases B (broad migration) and C (surface removal of `cross`/`cur`/`rlm`)
are entirely follow-on PRs.

## Open issues surfaced by this work

1. **Testing-harness gap for v3a unit tests**. v2's pattern
   `testing.SetRealm(NewUserRealm(alice)) + func(cur realm){...}(cross2(cur))`
   manufactures a crossing frame so `cur.Previous()` resolves. v1's
   `runtime.Caller()` has no crossing frame to walk to; calling it
   directly under `testing.SetRealm` panics with "frame not found:
   cannot seek beyond origin caller override". Affected: `ownable/v1`'s
   mutating-method unit tests (omitted in this PR, covered by canary
   filetest instead). Phase-B migrated tests work around this by
   keeping `func(cur realm){...}(cross)` scaffolding inside test
   bodies.

   Investigated implementing `testing.WithCallerRealm(rlm, fn func())`
   in pure Gno; rejected because the testing stdlib is a non-realm
   package and the preprocessor forbids crossing function declarations
   / literals there (`crossing function literal declared in non-realm
   package`). A clean implementation needs a native binding that
   pushes a synthetic crossing frame onto `m.Frames` before invoking
   `fn`. Deferred to a follow-up PR.

2. **Pre-existing test failures on `pr-5669` base**. The PR base has
   several pre-existing test failures (`addressable_1b_err.gno`,
   `zrealm_p_convert_readonly_ok_filetest.gno`, slice/varg tests).
   Confirmed unrelated to this stack — failures reproduce on
   `9d560263d` without these commits applied.

## Verification

For each commit, verified:
- Targeted filetest passes (`go test ./pkg/gnolang/ -run Files/<name>`).
- No new regressions in `Files/zrealm*` suite (only pre-existing
  baseline failures remain).
- ownable/v1 unit tests pass via `gno test`.

## References

- `gnovm/adr/interrealm_v2.md` — v2 design and phasing.
- `gnovm/adr/interrealm_v3a.md` — v3a design (the committed plan).
- `gnovm/adr/interrealm_v3b.md` — optional type-qualifier extension.
- `gnovm/adr/interrealm_discipline.md` — library discipline rules.
- `gnovm/adr/interrealm_capability_levels.md` — escalation options
  if discipline is insufficient.
- `docs/resources/gno-security.md` — threat-class taxonomy.
- `docs/resources/gno-interrealm.md` — interrealm semantics.

## Reviewer guidance

- **Read order**: this ADR → `interrealm_v3a.md` → individual commits
  in stack order.
- **What to verify**: each commit is self-contained and reviewable
  independently. The stack is non-breaking — every v2 surface still
  works; v3a additions coexist.
- **What to push back on**: the deferred items (OriginRealm,
  call-form analyzer, testing-harness gap). These are real Phase A
  work that hasn't shipped yet; if reviewers want them in this PR,
  the scope expands significantly.
