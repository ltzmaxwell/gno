// PKGPATH: gno.land/r/launderrh_mv_plainhook_apply
package launderrh_mv_plainhook_apply

// Stored PlainHook (func()) that captures a /p/-typed pointer aliasing
// victim memory and dispatches its /p/-Apply method later, with a
// /p/-declared callback.
//
// Trace:
//   1. main → m.Realm = /r/launderrh_mv_plainhook_apply
//   2. RegisterPlainHook(closure) — borrow rule #1 → m.Realm = /r/-victim,
//      closure stored.
//   3. RunPlainHooks() — borrow rule #1 → m.Realm = /r/-victim. Body: h().
//   4. h is /r/-attacker-declared → borrow rule #1 → m.Realm = /r/-attacker.
//   5. Inside h: captured.Apply(EvilWrite). Apply is a /p/-method on
//      *launderpkg.Immutable; recv is captured *launderpkg.Immutable
//      aliasing victim memory. borrow rule #2 → m.Realm = /r/-victim.
//   6. EvilWrite entered the Apply borrow stamped /r/-attacker → rule #3
//      → runs as attacker → write refused.
//
// Outcome: refused, like the plain Apply-callback attack; storing the
// hook changes nothing either way.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

func main(cur realm) {
	launderrvictim.ClearHooks()
	println("before:", launderrvictim.ReadEmbed())

	we := launderrvictim.GetWithEmbed()
	captured := &we.Immutable

	launderrvictim.RegisterPlainHook(func() {
		captured.Apply(launderattack.EvilWrite)
	})
	launderrvictim.RunPlainHooks()

	println("after: ", launderrvictim.ReadEmbed())
}

// Output:
// before: embed-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
