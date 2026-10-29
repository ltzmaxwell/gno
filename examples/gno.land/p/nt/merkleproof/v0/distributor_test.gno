package merkleproof

import (
	"bytes"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

type entry struct {
	index   uint64
	account address
	amount  int64
}

func fixture() ([]entry, *Tree) {
	entries := []entry{
		{0, testutils.TestAddress("alice"), 100},
		{1, testutils.TestAddress("bob"), 250},
		{2, testutils.TestAddress("carol"), 1},
		{3, testutils.TestAddress("dave"), -7}, // negative amounts encode too
		{4, testutils.TestAddress("erin"), 1 << 40},
	}
	hashes := make([][]byte, len(entries))
	for i, e := range entries {
		hashes[i] = AirdropLeaf(e.index, e.account, e.amount)
	}
	tree, _ := NewTree(hashes)
	return entries, tree
}

func TestDistributorClaim(t *testing.T) {
	entries, tree := fixture()
	d, err := NewDistributor(tree.Root())
	if err != nil {
		t.Fatalf("NewDistributor: %v", err)
	}
	if !bytes.Equal(d.Root(), tree.Root()) {
		t.Error("Root does not round trip")
	}

	for i, e := range entries {
		proof, _ := tree.Proof(i)
		if d.Claimed(e.index) {
			t.Errorf("entry %d claimed before any call", i)
		}
		if !d.Verify(e.index, e.account, e.amount, proof) {
			t.Errorf("entry %d did not verify", i)
		}
		if err := d.Claim(e.index, e.account, e.amount, proof); err != nil {
			t.Errorf("entry %d: Claim: %v", i, err)
		}
		if !d.Claimed(e.index) {
			t.Errorf("entry %d not marked claimed", i)
		}
	}
	if got := d.ClaimCount(); got != uint64(len(entries)) {
		t.Errorf("ClaimCount = %d, want %d", got, len(entries))
	}
}

func TestDistributorRejects(t *testing.T) {
	entries, tree := fixture()
	d, _ := NewDistributor(tree.Root())
	proof0, _ := tree.Proof(0)
	proof1, _ := tree.Proof(1)
	e0, e1 := entries[0], entries[1]

	tests := []struct {
		name    string
		index   uint64
		account address
		amount  int64
		proof   [][]byte
		want    error
	}{
		{"wrong amount", e0.index, e0.account, e0.amount + 1, proof0, ErrBadProof},
		{"wrong account", e0.index, e1.account, e0.amount, proof0, ErrBadProof},
		{"wrong index", e1.index, e0.account, e0.amount, proof0, ErrBadProof},
		{"another entry's proof", e0.index, e0.account, e0.amount, proof1, ErrBadProof},
		{"empty proof", e0.index, e0.account, e0.amount, nil, ErrBadProof},
		{"index nobody holds", 99, e0.account, e0.amount, proof0, ErrBadProof},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := d.Claim(tt.index, tt.account, tt.amount, tt.proof); err != tt.want {
				t.Errorf("Claim = %v, want %v", err, tt.want)
			}
			if d.ClaimCount() != 0 {
				t.Error("a rejected claim marked a bit")
			}
		})
	}

	// A rejected claim must leave the entry claimable.
	if err := d.Claim(e0.index, e0.account, e0.amount, proof0); err != nil {
		t.Errorf("valid claim after rejections: %v", err)
	}
	// And a repeat must not pay twice.
	if err := d.Claim(e0.index, e0.account, e0.amount, proof0); err != ErrAlreadyClaimed {
		t.Errorf("repeat claim = %v, want ErrAlreadyClaimed", err)
	}
	if d.ClaimCount() != 1 {
		t.Errorf("ClaimCount = %d, want 1", d.ClaimCount())
	}
}

func TestNewDistributorRejectsBadRoot(t *testing.T) {
	if _, err := NewDistributor(nil); err != ErrBadRoot {
		t.Errorf("nil root = %v, want ErrBadRoot", err)
	}
	if _, err := NewDistributor(make([]byte, 31)); err != ErrBadRoot {
		t.Errorf("short root = %v, want ErrBadRoot", err)
	}
}

// TestAirdropLeafIsUnambiguous checks the length prefix does its job: no two
// distinct entries share an encoding.
func TestAirdropLeafIsUnambiguous(t *testing.T) {
	a := testutils.TestAddress("alice")
	b := testutils.TestAddress("bob")

	seen := map[string]string{}
	add := func(label string, leaf []byte) {
		key := string(leaf)
		if prev, ok := seen[key]; ok {
			t.Errorf("%s collided with %s", label, prev)
		}
		seen[key] = label
	}
	add("0/alice/100", AirdropLeaf(0, a, 100))
	add("1/alice/100", AirdropLeaf(1, a, 100))
	add("0/bob/100", AirdropLeaf(0, b, 100))
	add("0/alice/101", AirdropLeaf(0, a, 101))
	add("0/alice/-100", AirdropLeaf(0, a, -100))
	add("max index", AirdropLeaf(^uint64(0), a, 100))

	// Deterministic across calls.
	if !bytes.Equal(AirdropLeaf(7, a, 42), AirdropLeaf(7, a, 42)) {
		t.Error("AirdropLeaf is not deterministic")
	}
}

func TestBitmap(t *testing.T) {
	b := NewBitmap()
	if b.Get(0) || b.Count() != 0 {
		t.Error("fresh bitmap is not empty")
	}
	// Indices chosen to straddle word boundaries.
	for _, i := range []uint64{0, 1, 63, 64, 65, 127, 128, 1 << 20} {
		if !b.Set(i) {
			t.Errorf("first Set(%d) returned false", i)
		}
		if !b.Get(i) {
			t.Errorf("Get(%d) false after Set", i)
		}
		if b.Set(i) {
			t.Errorf("second Set(%d) returned true", i)
		}
	}
	if got := b.Count(); got != 8 {
		t.Errorf("Count = %d, want 8", got)
	}
	// Neighbours must be untouched.
	for _, i := range []uint64{2, 62, 66, 129, 1<<20 + 1} {
		if b.Get(i) {
			t.Errorf("Get(%d) true but never set", i)
		}
	}
}

func TestBitmapNilSafe(t *testing.T) {
	var b *Bitmap
	if b.Get(5) {
		t.Error("nil bitmap reported a set bit")
	}
	if b.Count() != 0 {
		t.Error("nil bitmap has a count")
	}
	// The zero value must be usable without NewBitmap.
	var z Bitmap
	if !z.Set(3) || !z.Get(3) {
		t.Error("zero-value Bitmap is not usable")
	}
}
