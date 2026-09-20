# PRxxxx: Versioned private redeploy carries the realm's globals

Status: proof of concept, draft PR. Design notes and the wider proposal:
RFC #694 (closed 2024-10), #2191, #4682.

## Context

A gno.land path is permanent. The one exception, a `private = true`
realm, may be redeployed by its creator, but the redeploy reruns `init`
over fresh globals and abandons the old object graph (#4949). So every
upgrade pattern in use (proxy + registry as in `r/gov/dao`, lazy copies,
clockworkgr/gno-upgradeable) moves state by copying it into a realm at a
new path, and pays for it twice: storage for both copies, and a new type
identity for every declared type, since `DeclaredTypeID` is pkgpath +
name.

The VM already reserves the machinery. `RunMemPackageOverRealm` hands a
redeploy the prior realm's ObjectID counter and deposit, and every
package-level variable is wrapped in a heap item so that, per
`docs/resources/gno-memory-model.md`, mutable realms could later
"swizzle" them.

## Decision

A `version` field in `gnomod.toml`. A private redeploy that steps it by
exactly one keeps the realm's state:

- `runMemPackage` reads the version itself: over a prior realm it plans
  the carry from the package still live in the store (every global by
  name, with its heap item's ObjectID and static TypeID; every declared
  type's underlying TypeID; the prior package block), then replaces the
  cached package value instead of refusing a cached one. Both keeper
  paths, AddPackage and EnablePackage, run it unchanged.
- The plan is applied after preprocessing and before any declaration
  runs. Each carried slot of the new package block is pointed at the
  prior heap item, whose declaration is then skipped. The prior block
  keeps its other slots but drops the carried ones, so the cleanup
  #4949 asks for cannot later count the live items as its own.
- Declared types are re-persisted with `Store.ReplaceType` on every
  redeploy, versioned or not, so objects loaded afterwards resolve to
  the new definition, methods included. `SetType` keeps whatever is
  cached, and the live package's types are cached by the time a
  redeploy saves, so the old redeploy served stale methods to any
  object it created.
- `migrate()` runs once in place of `init()`. `IsPkgInitFunc` gives it
  the same unreferenceable `migrate.N` suffix as `init`.
- Refused by the shared gnomod rules, on all three deploy paths, with
  the realm left as it was: a version that does not step by one, or
  without `private`. Refused by the plan: a global removed, retyped or
  turned into a non-variable; a declared type removed or given a
  different underlying type.

Version unset on both sides is the old redeploy, unchanged.

## Alternatives

- New path per version (`/v2`), state copied: today's practice; cannot
  keep type identity or importers.
- `pkg@hash` or semver in the path (#694): the path changes, so the same
  copying follows.
- Auto-converting "convertible" type changes (#694, thehowl): harder to
  make deterministic than refusing and asking for a two-step migrate.

## Consequences

- Axioms 1 and 2 of the design note are demonstrated end to end
  (`redeploy_versioned_state.txtar`): same path, state carried, typed
  migration, new methods on old objects, survives restart.
- Still private-only: importers and an authority other than the creator
  are follow-ups, as are a typed `path@N` import for reading removed or
  retyped globals from `migrate`, appended struct fields, an
  exported-API compatibility check, and refusing a redeploy over
  persisted func-lit closures whose source moved.
- The prior blocks are not deleted; that leak predates this change
  (#4949). The carried objects are re-adopted, not re-charged.
- The inert path takes the same run and the same rules, but is not
  exercised by the new txtar.
- `IsPkgInitFunc` is read by the VM front end only; the parser,
  transpiler and `gno fix` still special-case `init` by name.
