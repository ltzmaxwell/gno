# KnownDivergence (🔵) review

A review of the `// KnownDivergence:` bucket in [MIGRATION.md](MIGRATION.md).
Each blessed divergence becomes a **permanent consensus commitment at
mainnet** (fixing one later is itself a behavior change), so the bucket must
be vetted, not accumulated.

Finding: the bucket is a mix of genuinely-accepted divergences, entries that
are actually deferred bugs mis-parked as "accepted," and untriaged
auto-classifications. **No confirmed urgent bug hides here** — the
scary-looking entries are all static rejects (caught at deploy) or covered by
open PRs. The remaining work is reclassification + note-enrichment + a few
`/gno-triage` re-runs, not bug-fixing.

Method note: verify a run-mode file IN PLACE via
`go test ... -run 'TestFiles/gocorpus/testdata/<path>'`. Extracting it to a
plain `tests/files/*.gno` runs a different execution mode and misleads.

## A. Mislabeled — deferred, not accepted (all NON-urgent, static rejects)

Urgency is set by the error *stage*: these error at preprocess/type-check
(`file:line:col:` form) → caught at deploy, nothing ships → 🟠 Over-strict,
not a runtime divergence.

- `fixedbugs/issue54467.go` — `*(*[32]byte)(s)` slice→array-**pointer** (a
  go1.17 feature Gno targets). Over-strict reject. Tracked: PR #5599, issue
  #3501; prior closed #4337/#4344 missed the pointer form.
- `float_lit2.go` — near-max float32 constant conversion rejected. apd
  float-constant family; tracked by PR #5867 (apd→big.Rat), issue #5862.
- runtime/GC cluster — `gc.go`, `stackobj2.go`, `fixedbugs/issue7944.go`,
  `issue8132.go`, `issue71932.go`: nil-deref around `new(...)` + `runtime.GC()`.
  `/gno-triage` to classify bug vs divergence; "runtime thing" is not a blessing.

## B. Genuine divergences — keep, enrich the note

- `ken/string.go` — `println` inter-argument spacing (`a -b` vs `a-b`);
  `println` output is not language-spec'd. Legit.
- Version-gap (correct rejections at the go1.17 pin): `fixedbugs/issue67255.go`
  (range-over-int, go1.22), `issue71675.go` (range-over-func, go1.23),
  `range3.go` (range-over-int), `issue64565.go` (`max` builtin, go1.21).
  Classification call: arguably **Unsupported** (feature gap) not KnownDivergence.
- runtime stack-introspection: `fixedbugs/bug348.go`, `issue27201.go`,
  `issue4562.go`, `issue5856.go` — assert `runtime.Caller` location; Gno lacks
  it. Likely **Unsupported**.
- `fixedbugs/issue7419.go` — apd exponent limit; same family as issue11326b →
  PR #5867.

## C. Untriaged — auto-classified, never decided

`fixedbugs/bug352.go`, `bug409.go`, `issue21808.go`, `issue35576.go`,
`issue43444.go`, `issue6899.go` — carry the harness default
`KnownDivergence: TODO: <category>: explain…`. Must be triaged, not blessed
by default.

## Tracking — no new issues needed (all covered)

- slice→array-pointer: PR #5599, issue #3501.
- apd float-constant family (float_lit2, issue11326b, issue7419): PR #5867
  (replaces the apd BigdecValue path), issue #5862 — so these are NOT permanent
  apd limits; re-triage against #5867 before blessing.

## Recommendation

Before this suite's verdict layer is presented as launch-ready: `/gno-triage`
across A + C (oracle vs real Go — several will change buckets); enrich B's
notes and settle the KnownDivergence-vs-Unsupported call on the version-gap /
runtime-Caller sets. Only the substantively-noted entries are review-clean
today. Do not present the raw count as "vetted divergences."
