// PKGPATH: gno.land/r/launderrh_mv_higher_order_chain
package launderrh_mv_higher_order_chain

// Higher-order indirection chain: victim calls fn that calls fn that
// calls attacker's STORED PlainHook, which dispatches /p/-Apply
// against a captured /r/-victim-stamped /p/-pointer.
//
// 1. main → m.Realm = /r/-attacker
// 2. RegisterPlainHook(closureA) — borrow rule #1 → victim. closureA stored.
// 3. main calls runViaTrampoline() — local helper that wraps the
//    victim call inside another function value indirection.
// 4. trampoline() invokes launderrvictim.RunPlainHooks(). borrow rule #1 →
//    m.Realm = /r/-victim.
// 5. RunPlainHooks calls closureA() — /r/-attacker body → borrow rule #1 →
//    m.Realm = /r/-attacker.
// 6. Inside closureA: chainHelper() — local /r/-attacker function
//    that further indirects to captured.Apply(EvilWrite).
// 7. Apply is /p/-method, recv is /r/-victim-stamped → borrow rule #2 →
//    m.Realm = /r/-victim during Apply.
// 8. EvilWrite entered the Apply borrow stamped /r/-attacker → rule #3
//    → runs as attacker → write refused.
//
// Indirection chaining changes nothing either way: the callback's
// stamp, not the wrapper layers, decides the write.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/p/demo/tests/launderpkg/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

var captured *launderpkg.Immutable

func chainHelper() {
	captured.Apply(launderattack.EvilWrite)
}

func trampoline(fn func()) {
	fn()
}

func main(cur realm) {
	launderrvictim.ClearHooks()
	println("before:", launderrvictim.ReadEmbed())

	we := launderrvictim.GetWithEmbed()
	captured = &we.Immutable

	launderrvictim.RegisterPlainHook(func() {
		chainHelper()
	})
	trampoline(launderrvictim.RunPlainHooks)

	println("after: ", launderrvictim.ReadEmbed())
}

// Output:
// before: embed-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
