package merkleproof

import (
	"bytes"
	"crypto/keccak256"
	"errors"
)

// HashSize is the length in bytes of every hash this package produces or
// accepts.
const HashSize = keccak256.Size

var (
	// ErrBadHashLength is returned when a root, leaf or proof element is not
	// HashSize bytes long.
	ErrBadHashLength = errors.New("merkleproof: hash must be 32 bytes")
	// ErrBadProof is returned when a proof does not reconstruct the root.
	ErrBadProof = errors.New("merkleproof: proof does not match the root")
	// ErrNoLeaves is returned when a tree is built over an empty list.
	ErrNoLeaves = errors.New("merkleproof: no leaves")
	// ErrIndexOutOfRange is returned for an index no leaf occupies.
	ErrIndexOutOfRange = errors.New("merkleproof: index out of range")
)

// LeafHash returns the leaf commitment for arbitrary data: keccak256 applied
// twice.
//
// The second application is what makes a proof unforgeable. Internal nodes are
// a single keccak256 of two concatenated children, so a caller who could
// choose a 64-byte leaf could present an internal node as a leaf and claim a
// position that was never committed. Double hashing puts leaves and internal
// nodes in disjoint preimage spaces. Any off-chain generator must hash leaves
// the same way.
func LeafHash(data []byte) []byte {
	first := keccak256.Sum256(data)
	second := keccak256.Sum256(first[:])
	return second[:]
}

// HashPair returns the parent of two nodes: keccak256 of the two hashes
// concatenated in ascending byte order. Sorting is what lets a proof omit the
// direction of each step.
func HashPair(a, b []byte) []byte {
	var buf [2 * HashSize]byte
	if bytes.Compare(a, b) <= 0 {
		copy(buf[:HashSize], a)
		copy(buf[HashSize:], b)
	} else {
		copy(buf[:HashSize], b)
		copy(buf[HashSize:], a)
	}
	sum := keccak256.Sum256(buf[:])
	return sum[:]
}

// Process folds leaf through proof and returns the root it implies. The result
// is meaningful only when compared against a root committed in advance.
func Process(leaf []byte, proof [][]byte) ([]byte, error) {
	if len(leaf) != HashSize {
		return nil, ErrBadHashLength
	}
	node := leaf
	for _, sibling := range proof {
		if len(sibling) != HashSize {
			return nil, ErrBadHashLength
		}
		node = HashPair(node, sibling)
	}
	return node, nil
}

// Verify reports whether leaf sits under root at the position proof describes.
func Verify(root, leaf []byte, proof [][]byte) bool {
	if len(root) != HashSize {
		return false
	}
	got, err := Process(leaf, proof)
	if err != nil {
		return false
	}
	return bytes.Equal(got, root)
}

// Root returns the Merkle root of leaves, which must already be leaf hashes.
//
// The construction an off-chain generator has to match: hash each adjacent
// pair with [HashPair], and when a level holds an odd number of nodes carry
// the last one up unchanged rather than duplicating it. A single leaf is its
// own root.
func Root(leaves [][]byte) ([]byte, error) {
	t, err := NewTree(leaves)
	if err != nil {
		return nil, err
	}
	return t.Root(), nil
}

// Tree is a built Merkle tree, kept only to produce proofs. Realms normally
// store just a root and let callers bring their own proofs; build a Tree when
// the list is small enough to live on chain, or in tests.
type Tree struct {
	levels [][][]byte // levels[0] is the leaves, the last level is the root
}

// NewTree builds the tree described by [Root] over leaves, which must already
// be leaf hashes.
func NewTree(leaves [][]byte) (*Tree, error) {
	if len(leaves) == 0 {
		return nil, ErrNoLeaves
	}
	level := make([][]byte, len(leaves))
	for i, l := range leaves {
		if len(l) != HashSize {
			return nil, ErrBadHashLength
		}
		level[i] = l
	}

	t := &Tree{levels: [][][]byte{level}}
	for len(level) > 1 {
		next := make([][]byte, 0, (len(level)+1)/2)
		for i := 0; i+1 < len(level); i += 2 {
			next = append(next, HashPair(level[i], level[i+1]))
		}
		if len(level)%2 == 1 {
			// Odd node out: carry it up rather than pairing it with itself,
			// which would let its proof be replayed one level down.
			next = append(next, level[len(level)-1])
		}
		t.levels = append(t.levels, next)
		level = next
	}
	return t, nil
}

// Root returns the tree's root hash.
func (t *Tree) Root() []byte { return t.levels[len(t.levels)-1][0] }

// Len returns the number of leaves.
func (t *Tree) Len() int { return len(t.levels[0]) }

// Leaf returns the leaf hash at index.
func (t *Tree) Leaf(index int) ([]byte, error) {
	if index < 0 || index >= t.Len() {
		return nil, ErrIndexOutOfRange
	}
	return t.levels[0][index], nil
}

// Proof returns the sibling hashes proving the leaf at index. A carried odd
// node contributes no sibling at that level, so proofs are not all the same
// length.
func (t *Tree) Proof(index int) ([][]byte, error) {
	if index < 0 || index >= t.Len() {
		return nil, ErrIndexOutOfRange
	}
	proof := [][]byte{}
	for d := 0; d < len(t.levels)-1; d++ {
		level := t.levels[d]
		sibling := index ^ 1
		if sibling < len(level) {
			proof = append(proof, level[sibling])
		}
		index /= 2
	}
	return proof, nil
}
