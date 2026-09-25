// Package launderplugin is a realm that hands out a /p/ function value
// as a return value, the mirror of passing one in as an argument.
package launderplugin

import (
	"gno.land/p/demo/tests/launderattack/v0"
	"gno.land/p/demo/tests/launderpkg/v0"
)

// Handler returns a /p/-declared function. Leaving this realm as a
// result stamps it with launderplugin, so a caller that invokes it on
// its own handle runs it as launderplugin and the write is refused.
func Handler() func(*launderpkg.Immutable) {
	return launderattack.EvilWrite
}
