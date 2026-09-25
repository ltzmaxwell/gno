# Stamp `/p/` function values handed across a realm boundary

## Status

Proposed.

## Context

A top-level `/p/` function has no authority of its own: no declaring
realm (borrow rule #1), no receiver (rule #2), no creator (rule #3). So it
runs as whoever calls it. That is what makes `/p/` helpers useful, and it
is also the (B)/(C) vector in `gno-security-guide.md`: a realm that invokes
a caller-supplied `/p/` function on one of its own handles, directly
(`ApplyHook(fn func(*somelib.Ledger))`) or through a `/p/` method that
passes its receiver along (`avl.Node.Iterate(cb)`, `Immutable.Apply(fn)`),
runs attacker-chosen code as itself, and the write commits. Twelve
`zrealm_launder_rdata_*` probes pinned this as known-open. The guide's
remedy, typing the callback parameter with an `/r/`-declared type, is a
per-site discipline and does not reach `/p/` types the realm already
embeds.

## Decision

A `/p/` `FuncDecl` value that crosses a realm boundary is copied and
stamped with the realm it came from, and rule #3 borrows to that stamp
when it is invoked, exactly as if the sender had wrapped it in a closure.

- Boundary: a call whose body runs in a realm other than the caller's
  (cross-call or any borrow), in both directions: arguments in
  (`stampCrossingArgs`, from `doOpCall` and the defer path) and results
  out (`PopFrameAndReturn`).
- Marker: the stamp lives in the value's `ObjectInfo.ID.PkgID`, which is
  already persisted. A canonical `/p/` FuncDecl carries its package's
  immutable PkgID; a realm PkgID on a non-closure can only be a stamp.
  Rule #3's gate becomes `IsClosure || PkgID.IsRealmPkg()`; `/r/` FuncDecls
  never reach it (rule #1 returns first). No new field, no amino change.
- Untouched: a `/p/` function named in the realm's own source and run
  there (no boundary crossed); stdlib values (trusted, run as the caller);
  closures (already stamped); a stamped value crossing again (keeps its
  first stamp, the least authority).
- Ephemeral senders: a stamp from a `maketx run` realm is fine inside the
  tx, but finalize would adopt the object into the storing realm and the
  value would run as that realm from the next tx on. `assignNewObjectID`
  refuses to persist such a value instead.

## Alternatives

- **Static vs dynamic call site.** Count only values called through a
  variable. The VM cannot tell `f := p.F; f()` in the realm's own source
  from a handed-in value without preprocess annotations.
- **`safely(cb)`.** Opt-in per hook site; every site an author forgets
  stays open. It composes with the stamp for callers that want zero
  authority rather than the sender's.
- **A new `Origin` field.** Explicit, but a persisted-shape change and a
  `pb3_gen` regeneration for one bit the PkgID already encodes.
- **Stamp composites too.** A `/p/` value nested in a struct, slice or map
  crosses unstamped; walking arguments is unbounded. Left open; the guide's
  type pin still covers it.

## Consequences

- The twelve Apply-callback probes flip to refused; `/p/` helpers named
  and run by the realm itself are unchanged (`zrealm_launder_h_pcallback`
  and the rest of the suite pass as before).
- Returning a `/p/` function value now grants the caller your authority
  for that function, as returning a closure always has. Realms should not
  return `/p/` functions that write through their parameters.
- One `FuncValue.Copy` per `/p/` function value that crosses a boundary,
  charged as allocation; `sameRealm` gains a pointer fast path since it now
  runs on every call and return.
- Tests: `zrealm_pfunc_stamp_own_handle.gno` (sender's own handle writes,
  victim's is refused, same-realm call unchanged),
  `zrealm_pfunc_stamp_returned.gno` (result direction),
  `pfunc_stamp_ephemeral.txtar` (in-tx use works, persisting is refused).
