// PKGPATH: gno.land/r/launderrh_mv_method_value
package launderrh_mv_method_value

// Method-value laundering probe.
//
// Bind `Apply` method to a /r/-victim's WithEmbed receiver, save the
// method value into an /r/-attacker local variable, THEN invoke it
// later with the attacker's /p/-declared callback. Question:
//   Does the method value remember the recv stamp (/r/launderrvictim)?
//   When invoked from /r/-attacker context, does borrow rule #2 still fire?
//
// Trace expectation:
//   1. main → m.Realm = /r/launderrh_mv_method_value
//   2. mv := we.Apply — bound method value captures recv (we), recv
//      base is /r/launderrvictim-stamped.
//   3. mv(EvilWrite) — invoke later. PushFrameCall sees stamped recv,
//      borrow rule #2 → m.Realm = /r/launderrvictim
//   4. EvilWrite entered the victim borrow as an argument → stamped
//      attacker → rule #3 → runs as attacker → write refused.
//
// Method values preserve receiver borrowing; the callback's stamp, not
// the method value, decides the write.

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

func main(cur realm) {
	println("before:", launderrvictim.ReadEmbed())

	we := launderrvictim.GetWithEmbed()
	mv := we.Apply // bound method value
	mv(launderattack.EvilWrite)

	println("after: ", launderrvictim.ReadEmbed())
}

// Output:
// before: embed-orig

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
