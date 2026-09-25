// PKGPATH: gno.land/r/pfunc_returned
package pfunc_returned

// The return direction: a /p/ function value another realm hands back
// is stamped with that realm, so invoking it on our own handle runs it
// as launderplugin and the write is refused. Otherwise a realm asking a
// plugin for its handler would run attacker-chosen /p/ code as itself.

import (
	"gno.land/p/demo/tests/launderpkg/v0"
	"gno.land/r/tests/vm/launderplugin"
)

var mine = &launderpkg.Immutable{Field: "mine-orig"}

func main(cur realm) {
	fn := launderplugin.Handler()
	fn(mine)
	println("after:", mine.Field)
}

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
