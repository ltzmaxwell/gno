package merkleproof

import (
	"bytes"
	"strconv"
	"testing"
)

func leaves(n int) [][]byte {
	out := make([][]byte, n)
	for i := 0; i < n; i++ {
		out[i] = LeafHash([]byte("entry-" + strconv.Itoa(i)))
	}
	return out
}

func TestLeafHashIsStableAndDistinct(t *testing.T) {
	a := LeafHash([]byte("x"))
	if len(a) != HashSize {
		t.Fatalf("leaf hash is %d bytes, want %d", len(a), HashSize)
	}
	if !bytes.Equal(a, LeafHash([]byte("x"))) {
		t.Error("LeafHash is not deterministic")
	}
	if bytes.Equal(a, LeafHash([]byte("y"))) {
		t.Error("distinct data collided")
	}
}

func TestHashPairIsOrderIndependent(t *testing.T) {
	a, b := LeafHash([]byte("a")), LeafHash([]byte("b"))
	if !bytes.Equal(HashPair(a, b), HashPair(b, a)) {
		t.Error("HashPair depends on argument order")
	}
	if bytes.Equal(HashPair(a, b), HashPair(a, a)) {
		t.Error("distinct pairs collided")
	}
}

// TestTreeShape pins the odd-carry rule an off-chain generator has to match.
func TestTreeShape(t *testing.T) {
	l := leaves(3)
	// Level 0: l0 l1 l2 -> level 1: H(l0,l1), l2 (carried) -> root.
	want := HashPair(HashPair(l[0], l[1]), l[2])
	got, err := Root(l)
	if err != nil {
		t.Fatalf("Root: %v", err)
	}
	if !bytes.Equal(got, want) {
		t.Error("three-leaf root does not follow the documented rule")
	}

	// A single leaf is its own root.
	one, err := Root(leaves(1))
	if err != nil {
		t.Fatalf("Root: %v", err)
	}
	if !bytes.Equal(one, leaves(1)[0]) {
		t.Error("single leaf is not its own root")
	}
}

func TestProofsVerifyForEverySize(t *testing.T) {
	for n := 1; n <= 9; n++ {
		l := leaves(n)
		tree, err := NewTree(l)
		if err != nil {
			t.Fatalf("n=%d: NewTree: %v", n, err)
		}
		root := tree.Root()
		for i := 0; i < n; i++ {
			proof, err := tree.Proof(i)
			if err != nil {
				t.Fatalf("n=%d i=%d: Proof: %v", n, i, err)
			}
			if !Verify(root, l[i], proof) {
				t.Errorf("n=%d: leaf %d did not verify", n, i)
			}
			// The same proof must not carry a different leaf.
			other := (i + 1) % n
			if n > 1 && Verify(root, l[other], proof) {
				t.Errorf("n=%d: leaf %d verified under leaf %d's proof", n, other, i)
			}
		}
	}
}

func TestVerifyRejectsTampering(t *testing.T) {
	l := leaves(8)
	tree, _ := NewTree(l)
	root := tree.Root()
	proof, _ := tree.Proof(5)

	if !Verify(root, l[5], proof) {
		t.Fatal("control case failed")
	}

	// A flipped bit anywhere in the proof.
	for i := range proof {
		bad := make([][]byte, len(proof))
		copy(bad, proof)
		mutated := make([]byte, HashSize)
		copy(mutated, proof[i])
		mutated[0] ^= 1
		bad[i] = mutated
		if Verify(root, l[5], bad) {
			t.Errorf("tampered proof element %d still verified", i)
		}
	}

	// A flipped bit in the root.
	badRoot := make([]byte, HashSize)
	copy(badRoot, root)
	badRoot[31] ^= 1
	if Verify(badRoot, l[5], proof) {
		t.Error("tampered root still verified")
	}

	// A dropped and an extra step.
	if Verify(root, l[5], proof[:len(proof)-1]) {
		t.Error("truncated proof verified")
	}
	if Verify(root, l[5], append(append([][]byte{}, proof...), l[0])) {
		t.Error("extended proof verified")
	}
}

func TestVerifyRejectsMalformedInput(t *testing.T) {
	l := leaves(4)
	tree, _ := NewTree(l)
	root := tree.Root()
	proof, _ := tree.Proof(0)

	if Verify(root[:31], l[0], proof) {
		t.Error("short root accepted")
	}
	if Verify(root, l[0][:31], proof) {
		t.Error("short leaf accepted")
	}
	if Verify(root, l[0], [][]byte{{1, 2, 3}}) {
		t.Error("short proof element accepted")
	}
	if _, err := Process(l[0][:10], nil); err != ErrBadHashLength {
		t.Errorf("Process error = %v, want ErrBadHashLength", err)
	}
}

func TestTreeErrors(t *testing.T) {
	if _, err := NewTree(nil); err != ErrNoLeaves {
		t.Errorf("NewTree(nil) = %v, want ErrNoLeaves", err)
	}
	if _, err := NewTree([][]byte{{1}}); err != ErrBadHashLength {
		t.Errorf("NewTree(short) = %v, want ErrBadHashLength", err)
	}
	tree, _ := NewTree(leaves(3))
	if _, err := tree.Proof(-1); err != ErrIndexOutOfRange {
		t.Error("negative index accepted")
	}
	if _, err := tree.Proof(3); err != ErrIndexOutOfRange {
		t.Error("index past the end accepted")
	}
	if _, err := tree.Leaf(3); err != ErrIndexOutOfRange {
		t.Error("Leaf past the end accepted")
	}
	if tree.Len() != 3 {
		t.Errorf("Len = %d, want 3", tree.Len())
	}
}

// TestInternalNodePassesAsLeaf pins the documented caveat: the low-level
// Verify trusts whatever leaf hash it is handed, so a 32-byte internal node
// verifies against the root. This is exactly why LeafHash hashes twice and
// why Distributor never lets a caller supply a leaf.
func TestInternalNodePassesAsLeaf(t *testing.T) {
	l := leaves(4)
	tree, _ := NewTree(l)
	root := tree.Root()

	internal := HashPair(l[0], l[1])
	sibling := HashPair(l[2], l[3])

	if !Verify(root, internal, [][]byte{sibling}) {
		t.Fatal("expected the low-level Verify to accept an internal node")
	}
	// But no input to LeafHash can land on that node short of a collision,
	// so nothing built through AirdropLeaf can exploit it.
	if bytes.Equal(LeafHash([]byte("anything")), internal) {
		t.Fatal("LeafHash collided with an internal node")
	}
}
