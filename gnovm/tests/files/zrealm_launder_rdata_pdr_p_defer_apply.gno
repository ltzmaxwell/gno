// PKGPATH: gno.land/r/launderrh_pdr_p_defer_apply
package launderrh_pdr_p_defer_apply

// Vector 7: /p/-method DeferApply schedules attacker callback as
// a defer rather than synchronous call.
//
// Trace:
//   1. main → m.Realm = /r/launderrh_pdr_p_defer_apply
//   2. inner := victim.GetWithPtr().Inner — read access fine
//   3. inner.DeferApply(EvilWrite) — borrow rule #2 receiver-borrow on
//      *launderpkg.Immutable (victim-stamped) → m.Realm = victim
//   4. DeferApply body: schedule fn(i) as defer
//   5. DeferApply returns → defer fires → PushFrameCall(fn, true)
//      with LastRealm = victim (current m.Realm)
//   6. fn is EvilWrite, stamped attacker when DeferApply took it →
//      rule #3 → m.Realm = attacker
//   7. EvilWrite body: i.Field = ... → readonly check fails → panic
//
// Same shape as the synchronous Apply case; the stamp is on the value,
// so defer adds no path around it.
//
// Expected: refused; the embedded /p/.Immutable is unchanged.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

func main(cur realm) {
	println("before:", launderrvictim.ReadPtr())

	inner := launderrvictim.GetWithPtr().Inner
	inner.DeferApply(launderattack.EvilWrite)

	println("after: ", launderrvictim.ReadPtr())
}

// Output:
// before: ptr-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
