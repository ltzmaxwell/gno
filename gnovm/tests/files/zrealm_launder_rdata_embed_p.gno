// PKGPATH: gno.land/r/launderrh_embed
package launderrh_embed

// /r/-declared victim with EMBEDDED /p/-type — Apply-callback attack.
//
// WithEmbed (in /r/launderrvictim) embeds launderpkg.Immutable by
// value. Method promotion gives WithEmbed an Apply method (from
// /p/launderpkg). The attacker calls Apply with a /p/-declared
// function value as the callback.
//
// Trace:
//   1. main → m.Realm = /r/launderrh_embed
//   2. we.Apply(EvilWrite) — promoted method, dispatches to
//      (*Immutable).Apply on &we.Immutable.
//      recv's base is the WithEmbed struct, /r/launderrvictim-stamped
//      borrow rule #2 → m.Realm = /r/launderrvictim
//   3. Inside Apply: fn(i) calls EvilWrite, which entered the borrow
//      as an argument and was stamped /r/launderrh_embed → rule #3 →
//      m.Realm = /r/launderrh_embed
//   4. Inside EvilWrite: i.Field = "..." → readonly check fails → panic.
//
// Embedding a /p/-type with Apply-style methods still hands Apply the
// victim's authority, but not a callback handed in from outside.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

func main(cur realm) {
	println("before:", launderrvictim.ReadEmbed())

	we := launderrvictim.GetWithEmbed()
	we.Apply(launderattack.EvilWrite)

	println("after: ", launderrvictim.ReadEmbed())
}

// Output:
// before: embed-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
