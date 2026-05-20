package loci

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

func TestLociStore(t *testing.T) {
	caller := testutils.TestAddress("caller")

	// The cross() wrapping below is a testing-harness workaround, not
	// part of the v3a API. It manufactures a crossing frame so that
	// runtime.Caller() inside Set has a transition to walk back to.
	// A future testing primitive (e.g., testing.WithCallerRealm) would
	// remove this scaffolding from v3a unit tests.

	t.Run("TestSet", func(t *testing.T) {
		testing.SetRealm(testing.NewUserRealm(caller))
		store := New()
		// Ensure that the value is nil before setting it.
		if r1 := store.Get(caller); r1 != nil {
			t.Errorf("expected value to be nil, got '%s'", r1)
		}
		func(cur realm) { store.Set([]byte("hello")) }(cross)
		if r2 := store.Get(caller); string(r2) != "hello" {
			t.Errorf("expected value to be 'hello', got '%s'", r2)
		}
		func(cur realm) { store.Set([]byte("world")) }(cross)
		if r3 := store.Get(caller); string(r3) != "world" {
			t.Errorf("expected value to be 'world', got '%s'", r3)
		}
	})
	t.Run("TestGet", func(t *testing.T) {
		testing.SetRealm(testing.NewUserRealm(caller))
		store := New()
		func(cur realm) { store.Set([]byte("hello")) }(cross)
		if r0 := store.Get(testutils.TestAddress("nil_user")); r0 != nil {
			t.Errorf("expected value to be nil, got '%s'", r0)
		}
		if r1 := store.Get(caller); string(r1) != "hello" {
			t.Errorf("expected value to be 'hello', got '%s'", r1)
		}
	})
}
