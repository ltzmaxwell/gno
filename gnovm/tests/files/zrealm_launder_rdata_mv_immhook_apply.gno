// PKGPATH: gno.land/r/launderrh_mv_immhook_apply
package launderrh_mv_immhook_apply

// Stored ImmHook (func(*launderrvictim.Immutable)) that uses its arg
// — given by victim — to dispatch /p/-Apply on an EMBEDDED /p/-pointer
// reached from the victim's /r/-Immutable.
//
// But our victim's Immutable is JUST { Field string }, no inner
// /p/-pointer. So this variant probes whether the attacker can still
// reach an exploit by capturing the /p/-Apply-bearing pointer from
// elsewhere and using the supplied arg as a "trigger".
//
// Effectively: ImmHook called from victim with i=gImm gives us
// nothing extra over RegisterPlainHook. But: the hook can CAPTURE the
// /p/-aliased pointer separately. The closure body is /r/-attacker
// → borrow rule #1 → m.Realm = /r/-attacker. From there, captured.Apply
// dispatches via borrow rule #2 to /r/-victim, and EvilWrite enters that
// borrow stamped /r/-attacker, so it runs as attacker.
//
// Outcome: refused, identical to the PlainHook variant. The ImmHook
// signature adds nothing either way; the callback's stamp decides.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/p/demo/tests/launderpkg/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

var captured *launderpkg.Immutable

func main(cur realm) {
	launderrvictim.ClearHooks()
	println("before:", launderrvictim.ReadEmbed())

	we := launderrvictim.GetWithEmbed()
	captured = &we.Immutable

	launderrvictim.RegisterHook(func(_ *launderrvictim.Immutable) {
		captured.Apply(launderattack.EvilWrite)
	})
	launderrvictim.RunHooks()

	println("after: ", launderrvictim.ReadEmbed())
}

// Output:
// before: embed-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
