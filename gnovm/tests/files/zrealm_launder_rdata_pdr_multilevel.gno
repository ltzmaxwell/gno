// PKGPATH: gno.land/r/launderrh_pdr_multilevel
package launderrh_pdr_multilevel

// Vector 10: multi-level chain — /r/-victim calls /p/-DeferApply
// which schedules attacker callback as a defer.
//
// Trace at deferred callback time:
//  1. main → m.Realm = attacker
//  2. CallPDeferApply(EvilWrite) → borrow rule #1 → m.Realm = victim
//  3. body: gWithPtr.Inner.DeferApply(fn) → receiver-borrow on
//     *launderpkg.Immutable victim-stamped — wait, m.Realm is
//     ALREADY victim, so the borrow check sees recvOID.PkgID ==
//     m.Realm.ID → no-op. m.Realm stays victim.
//  4. DeferApply body: schedule fn(i) as defer
//  5. DeferApply returns → defer fires → PushFrameCall(fn, true)
//     with LastRealm = victim (current m.Realm)
//  6. fn is EvilWrite, stamped attacker when CallPDeferApply took it
//     (step 2 changed the realm) → rule #3 → m.Realm = attacker
//  7. EvilWrite body: i.Field = ... → readonly check fails → panic
//
// Now CallPDeferApply returns (defer queue is empty). The /p/-frame
// is popped, restoring m.Realm to victim (unchanged). The /r/-victim
// frame is popped, restoring m.Realm to attacker.
//
// Expected: refused. The stamp is taken at the first realm change and
// survives the /p/ defer chain.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

func main(cur realm) {
	println("before:", launderrvictim.ReadPtr())

	launderrvictim.CallPDeferApply(launderattack.EvilWrite)

	println("after: ", launderrvictim.ReadPtr())
}

// Output:
// before: ptr-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
