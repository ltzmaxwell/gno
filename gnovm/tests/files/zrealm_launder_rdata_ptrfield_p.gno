// PKGPATH: gno.land/r/launderrh_pf
package launderrh_pf

// /r/-declared victim with /p/-POINTER FIELD — Apply-callback attack.
//
// WithPtr has `Inner *launderpkg.Immutable`. Attacker reads the
// pointer field, then calls Apply with a /p/-declared callback.
//
// Same trace as embed variant: Apply borrows m.Realm to victim, but
// EvilWrite entered that borrow stamped attacker (stampFuncValue) and
// runs as attacker (rule #3), so the write is refused.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

func main(cur realm) {
	println("before:", launderrvictim.ReadPtr())

	wp := launderrvictim.GetWithPtr()
	wp.Inner.Apply(launderattack.EvilWrite)

	println("after: ", launderrvictim.ReadPtr())
}

// Output:
// before: ptr-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
