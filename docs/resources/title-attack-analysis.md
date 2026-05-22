# Title() + PreviousRealm() Attack — Full Analysis (v1 → v2 → v3a)

## Demo code

```go
// ===== r/vault/vault.gno =====
package vault

import "chain/runtime"

var (
    owner    address
    onUpdate func(address, address)          // v1, v3a
    // onUpdate func(realm, address, address) // v2
)

func init() {
    owner = runtime.OriginCaller()           // v1, v3a
    // owner = cur.Previous().Address()      // v2
}

func SetCallback(fn func(address, address)) {              // v1, v3a
// func SetCallback(fn func(realm, address, address)) {   // v2
    onUpdate = fn
}

func TransferOwnership(newOwner address) {                 // v1, v3a
// func TransferOwnership(_ int, rlm realm, newOwner address) {  // v2
    // caller := runtime.PreviousRealm().Address()         // v1
    // if !rlm.IsCurrent() { panic(...) }                  // v2
    // if rlm.Previous().Address() != owner { panic(...) } // v2
    // caller := runtime.Caller().Address()                // v3a
    if caller != owner { panic("unauthorized") }
    owner = newOwner
    if onUpdate != nil {
        onUpdate(caller, newOwner)              // v1, v3a
        // onUpdate(rlm, caller, newOwner)      // v2
    }
}


// ===== r/attacker/attacker.gno =====
package attacker

import "gno.land/r/vault"

func init() {                                            // v1, v3a
// func init(cur realm) {                                // v2
    vault.SetCallback(func(prev, next address) {         // v1, v3a
    // vault.SetCallback(func(rlm realm, prev, next address) {  // v2
        vault.TransferOwnership(address("g1attacker"))   // v1, v3a
        // vault.TransferOwnership(0, cur, ...)          // v2 — replays captured cur
    })
}

func Trigger() {                                         // v1, v3a
// func Trigger(cur realm) {                             // v2
    vault.TransferOwnership(address("bob"))              // v1, v3a
    // vault.TransferOwnership(0, cur, address("bob"))   // v2
}
```

---

## Init phase

```
deployer deploys r/vault
  init(): owner = deployer_EOA
  onUpdate = nil

attacker deploys r/attacker
  init(): vault.SetCallback(attacker_closure)
    onUpdate = attacker_closure        ← attacker's code planted in vault
```

## Attack phase

deployer_EOA calls `vault.TransferOwnership(bob)`.

---

## v1 — `runtime.PreviousRealm()` (master)

```
CALL: EOA ──MsgCall──→ vault.TransferOwnership(bob)

fr   fn                                  m.Realm   LastRealm   crossing?
──   ──                                  ───────   ─────────   ─────────
3    vault.TransferOwnership(g1attacker)  vault     vault       no          ← RE-ENTRANT
2    attacker_closure()                   vault     vault       no          ← SKIP
1    vault.dispatch(onUpdate)             vault     vault       no          ← SKIP
0    vault.TransferOwnership(bob)         vault     EOA         yes (MsgCall)

PreviousRealm() walks UP from fr 3:
  fr 3: non-crossing → SKIP
  fr 2: non-crossing → SKIP
  fr 1: non-crossing → SKIP
  fr 0: MsgCall, crossing → land here
  → caller = EOA

CHECK at fr 3: EOA == deployer_EOA → TRUE
owner = g1attacker                  ← ATTACK SUCCEEDS
```

**Root cause:** injected callable runs without a realm transition. The stack walk skips non-crossing frames. Identity stolen.

---

## v2 — `cur realm` + `cur.Previous()` + `IsCurrent()` (PR #5669)

v2 makes the attacker's closure a realm transition (Layer 1 borrow:
/r/attacker-declared → m.Realm shifts vault → attacker). The attacker's
`cur` was minted during `init()` (a different MsgCall). When replayed at
attack time, `IsCurrent()` walks the LIVE frame stack and finds no
matching HIV — the frame that created this `cur` is gone. Attack blocked.

```
Attack time (new MsgCall, fresh frames):

fr   fn                                    m.Realm   LastRealm   rlm.IsCurrent()
──   ──                                    ───────   ─────────   ──────────────
3    vault.TransferOwnership(0, rlm, g1atk) vault     attacker    FALSE  ← stale cur from init()
2    attacker_closure(rlm, ...)            attacker  vault       —      ← rlm passed through, live
1    vault.dispatch(onUpdate)              vault     vault       —
0    vault.TransferOwnership(0, cur, bob)  vault     EOA         TRUE

Layer 1 fires at fr 2 (vault→attacker) and fr 3 (attacker→vault).

At fr 3: `rlm` is the attacker's `cur` captured during init() (a different
MsgCall). Its HIV was minted in the init frame — that frame is gone, the
current call chain has no frame with matching HIV. `IsCurrent()` → false.
→ ErrUnauthorized. Attack blocked.
```

**How v2 closes Title():** the declaring-realm borrow makes every
/r/-declared callable a realm transition. `IsCurrent()` catches replayed
`cur` values via HIV pointer identity against the live frame stack. A
`cur` from a past MsgCall cannot pass `IsCurrent()`.

**What v2 doesn't close:** if the **vault itself** explicitly passes its
live `cur` to the attacker's callback, the attacker can forward it right
back. `IsCurrent()` passes (matches vault's live frame). `cur.Previous()`
returns EOA = owner. This is vault handing the attacker a loaded gun —
a realm-author mistake, not a language bug.

---

## v3a — `runtime.Caller()` (current branch)

v3a closes even the "vault hands attacker a loaded gun" case. `Caller()`
doesn't read from any passed value — it walks `LastRealm` on the live
frame stack. Inside the re-entrant call, `Caller()` = r/attacker, not EOA.

```
CALL: EOA ──auto-cross──→ vault.TransferOwnership(bob)

fr   fn                                  m.Realm   LastRealm   shifted?     Caller()
──   ──                                  ───────   ─────────   ────────     ────────
3    vault.TransferOwnership(g1attacker)  vault     attacker    YES          attacker
2    attacker_closure()                   attacker  vault       YES          —
1    vault.dispatch(onUpdate)             vault     vault       NO           —
0    vault.TransferOwnership(bob)         vault     EOA         YES          EOA

Caller() reads fr. LastRealm from the live stack:
  fr 3's LastRealm = attacker.

CHECK at fr 3: attacker != deployer_EOA → FALSE
PANIC "unauthorized"                ← ATTACK BLOCKED
```

No `cur` value to capture, no `cur` value to replay, no `IsCurrent()`
guard needed. `Caller()` is a machine op — the VM reads the live stack
at call time. Every call gets a fresh, unforgeable answer.

---

## Summary

| | v1 | v2 | v3a |
|---|---|---|---|
| Mechanism | `PreviousRealm()` walk | `cur realm` value + `IsCurrent()` | `Caller()` machine op |
| Injected callable creates transition? | No | Yes (Layer 1 borrow) | Yes (Layer 1 borrow) |
| Identity-theft blocked? | No | Yes (`IsCurrent()` catches stale cur) | Yes (`Caller()` reads live stack) |
| Vault passes live cur, attacker forwards? | — | Passes (author error, not language bug) | Blocked (`Caller()` returns attacker) |
| Cur/rlm parameter needed? | No (uses `PreviousRealm()`) | Yes (`_ int, rlm realm, ...`) | No (uses `Caller()`) |
| Cross keyword needed? | No | Yes | No |
| Forgeable identity? | Yes (walk skips frames) | Yes (user types implement `realm` interface — omarsy) | No (`Realm` is concrete struct) |
| Re-entrance prevention | Author responsibility | Author responsibility | Author responsibility |
