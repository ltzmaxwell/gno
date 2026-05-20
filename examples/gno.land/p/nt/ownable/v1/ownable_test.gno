package ownable

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

// Unit tests cover the pure-data API surface (no caller-identity
// resolution). End-to-end behavior of TransferOwnership / DropOwnership
// under realistic call chains is verified by the filetest
// gnovm/tests/files/zrealm_v3a_canary_filetest.gno, which exercises
// the v3a-style canary realm /r/tests/vm/v3acanary.
//
// We don't write unit tests for the mutating methods here because the
// v2-style testing harness (testing.SetRealm + cross2(cur) wrappers) is
// exactly the ceremony v1 is designed to avoid. A v3a-aligned testing
// harness with a "push synthetic caller frame" primitive would let
// these tests be expressed naturally; for now, filetests carry the
// load for realm-aware scenarios.

func TestNewWithAddress(cur realm, t *testing.T) {
	o := NewWithAddress(alice)
	uassert.Equal(t, o.Owner(), alice)
}

func TestOwnedBy(cur realm, t *testing.T) {
	o := NewWithAddress(alice)
	uassert.True(t, o.OwnedBy(alice))
	uassert.False(t, o.OwnedBy(bob))
	uassert.False(t, o.OwnedBy(""))
}

func TestOwnedByNilReceiver(cur realm, t *testing.T) {
	var o *Ownable
	uassert.False(t, o.OwnedBy(alice))
}

func TestAssertOwnedBy(cur realm, t *testing.T) {
	o := NewWithAddress(alice)

	// alice is owner: AssertOwnedBy should not panic.
	o.AssertOwnedBy(alice)

	// bob is not owner: AssertOwnedBy should panic.
	panicked := false
	func() {
		defer func() {
			if r := recover(); r != nil {
				panicked = true
			}
		}()
		o.AssertOwnedBy(bob)
	}()
	uassert.True(t, panicked, "expected panic for non-owner")
}

func TestOwnerNilReceiver(cur realm, t *testing.T) {
	var o *Ownable
	uassert.Equal(t, o.Owner(), address(""))
}
