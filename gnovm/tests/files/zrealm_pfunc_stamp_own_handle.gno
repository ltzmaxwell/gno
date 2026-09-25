// PKGPATH: gno.land/r/pfunc_own_handle
package pfunc_own_handle

// A /p/ function value handed to another realm keeps the sender's
// authority. The victim runs EvilWrite while borrowed to itself, but the
// value entered stamped with this realm, so it borrows back here: the
// write to this realm's own object succeeds, and the same call on the
// victim's object is refused. Named in this realm's own source and run
// here, it stays this realm's code (Apply on our own object).

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/p/demo/tests/launderpkg/v0"
	"gno.land/r/tests/vm/launderrvictim"
)

var mine = &launderpkg.Immutable{Field: "mine-orig"}

func main(cur realm) {
	launderrvictim.ApplyTo(launderattack.EvilWrite, mine)
	println("own handle via victim:", mine.Field)

	mine.Field = "mine-orig"
	mine.Apply(launderattack.EvilWrite)
	println("own handle, own call:  ", mine.Field)

	// Refused, and the panic crosses a realm boundary, so it aborts.
	launderrvictim.ApplyTo(launderattack.EvilWrite, launderrvictim.GetWithPtr().Inner)
}

// Output:
// own handle via victim: pwnd-via-apply
// own handle, own call:   pwnd-via-apply

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,0)>.Field
