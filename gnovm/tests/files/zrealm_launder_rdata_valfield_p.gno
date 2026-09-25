// PKGPATH: gno.land/r/launderrh_vf
package launderrh_vf

// /r/-declared victim with /p/-VALUE FIELD — Apply-callback attack.
//
// WithVal has `Inner launderpkg.Immutable` (named, not embedded).
// Attacker takes the address of the inner field, then calls Apply.
// Same shape as the embed/pointer variants: EvilWrite enters Apply's
// victim borrow stamped with the attacker realm, so the write is refused.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

func main(cur realm) {
	println("before:", launderrvictim.ReadVal())

	wv := launderrvictim.GetWithVal()
	wv.Inner.Apply(launderattack.EvilWrite)

	println("after: ", launderrvictim.ReadVal())
}

// Output:
// before: val-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
