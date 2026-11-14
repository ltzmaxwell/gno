// PKGPATH: gno.land/r/demo/entrypclosure
package entrypclosure

import "gno.land/r/tests/vm/entryclosure"

// A closure built by library code acts for no realm: called by a stranger it
// cannot write the owner's objects. A closure written in the owner's source
// still writes, and the owner's own entry still writes through either kind.

func call(cur realm, f func()) { f() }

func main(cur realm) {
	println("p closure:", revive(func() { call(cross(cur), entryclosure.Incer()) }))
	println("p counter:", revive(func() { call(cross(cur), func() { entryclosure.Counter()() }) }))
	println("n:", entryclosure.N(), "count:", entryclosure.Count())
	entryclosure.LitIncer()()
	println("owner literal wrote:", entryclosure.N())
	entryclosure.OwnerInc(cross(cur))
	println("owner entry wrote:", entryclosure.N(), entryclosure.Count())
}

// Output:
// p closure: cannot modify object owned by another realm from library code (call a function of the owning realm): b<~VPBlock(1,0)>.N
// p counter: cannot modify object owned by another realm from library code (call a function of the owning realm): c<~VPBlock(1,1)>
// n: 0 count: 0
// owner literal wrote: 1
// owner entry wrote: 2 1
