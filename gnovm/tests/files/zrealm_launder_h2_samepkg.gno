// PKGPATH: gno.land/r/launderh2
package launderh2

// Attack H, SAME-PKG VARIANT: attacker's primitive-recv impl AND the
// mutable type it operates on are declared in the same /p/ package.
//
// The earlier narrow Attack-H patch (commit 9d560263d) checked
// `pdt.PkgPath != recvPkgPath` — fire the anchor only when the
// receiver's type pkg differs from the param's type pkg. That left
// a gap: when both types are in the same /p/ package, the predicate
// returned false and m.Realm stayed at the caller (victim's realm)
// during attacker code execution. Write to victim-owned data
// succeeded.
//
// Generalized anchor (drop the != check): the predicate now fires
// for any /p/-declared pointer param, regardless of whether it's in
// the same pkg as the receiver type. The outer `pid != m.Realm.ID`
// check in PushFrameCall still allows same-realm calls (e.g., calling
// your own /p/'s primitive method on your own /p/'s data), so the
// fix doesn't break legitimate same-realm intra-pkg patterns.
//
// Setup mirrors zrealm_launder_h_pcallback but uses
// launderpkg.SamePkgEvil — declared in the SAME /p/ package as
// launderpkg.Immutable.

import (
	"gno.land/p/demo/tests/launderpkg"
	"gno.land/r/tests/vm/laundervictim"
)

func main(cur realm) {
	gp := laundervictim.GetPtr()
	imm := laundervictim.GetImm()

	gp.UseMutator(imm, launderpkg.SamePkgEvil(0))
}

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): i<VPBlock(1,1)>.Field
