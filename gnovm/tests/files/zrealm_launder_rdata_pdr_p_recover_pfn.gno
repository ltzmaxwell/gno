// PKGPATH: gno.land/r/launderrh_pdr_p_recover_pfn
package launderrh_pdr_p_recover_pfn

// Vector 8b: /p/-method RecoverApply called with a top-level /p/
// callback (EvilWrite) — the known-open Apply attack, now inside
// a /p/-RecoverApply scope.
//
// Trace:
//  1. main → m.Realm = attacker
//  2. inner.RecoverApply(EvilWrite) → borrow rule #2 receiver-borrow on
//     *launderpkg.Immutable (victim-stamped) → m.Realm = victim
//  3. RecoverApply schedules defer { recover() } in /p/-frame
//  4. RecoverApply calls EvilWrite(i): the value entered the victim
//     borrow as an argument, so it is stamped attacker → rule #3 →
//     m.Realm = attacker
//  5. EvilWrite body: i.Field = ... → readonly check fails → panic
//  6. The panic crosses a realm boundary, so RecoverApply's recover
//     does not catch it.
//
// Expected: refused; same outcome as pdr_p_defer_apply but synchronous.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

func main(cur realm) {
	println("before:", launderrvictim.ReadPtr())

	inner := launderrvictim.GetWithPtr().Inner
	rec := inner.RecoverApply(launderattack.EvilWrite)
	if rec == nil {
		println("rec: nil (no panic, write succeeded)")
	} else {
		println("rec: non-nil")
	}

	println("after: ", launderrvictim.ReadPtr())
}

// Output:
// before: ptr-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
