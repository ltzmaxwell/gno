package merkleproof

import (
	"encoding/binary"
	"errors"
)

var (
	// ErrAlreadyClaimed is returned when an index has been claimed before.
	ErrAlreadyClaimed = errors.New("merkleproof: already claimed")
	// ErrBadRoot is returned when a root is not HashSize bytes long.
	ErrBadRoot = errors.New("merkleproof: root must be 32 bytes")
)

// Distributor is the airdrop shape: one committed root, plus a bit per index
// already paid out.
//
// The index is part of the leaf, so a proof for one entry cannot be replayed
// against another entry's bit. That binding is the reason [Distributor.Claim]
// builds the leaf itself from (index, account, amount) instead of accepting
// one from the caller; a realm with a different entry shape should use
// [Verify] directly and keep its own [Bitmap].
type Distributor struct {
	root    []byte
	claimed *Bitmap
}

// NewDistributor commits to root, which must be the root of a tree whose
// leaves are [AirdropLeaf] values.
func NewDistributor(root []byte) (*Distributor, error) {
	if len(root) != HashSize {
		return nil, ErrBadRoot
	}
	cp := make([]byte, HashSize)
	copy(cp, root)
	return &Distributor{root: cp, claimed: NewBitmap()}, nil
}

// Root returns a copy of the committed root.
func (d *Distributor) Root() []byte {
	cp := make([]byte, HashSize)
	copy(cp, d.root)
	return cp
}

// Claimed reports whether index has been claimed.
func (d *Distributor) Claimed(index uint64) bool { return d.claimed.Get(index) }

// ClaimCount returns how many entries have been claimed.
func (d *Distributor) ClaimCount() uint64 { return d.claimed.Count() }

// Verify reports whether the entry is in the committed tree, without claiming
// it. It ignores whether the entry has already been claimed.
func (d *Distributor) Verify(index uint64, account address, amount int64, proof [][]byte) bool {
	return Verify(d.root, AirdropLeaf(index, account, amount), proof)
}

// Claim verifies the entry and marks index as claimed. It returns
// [ErrAlreadyClaimed] for a repeat and [ErrBadProof] for an entry that is not
// in the tree, and marks nothing in either case.
//
// Claim decides only that the entry is valid and new; moving the funds is the
// caller's job, and must happen in the same transaction.
func (d *Distributor) Claim(index uint64, account address, amount int64, proof [][]byte) error {
	if d.claimed.Get(index) {
		return ErrAlreadyClaimed
	}
	if !Verify(d.root, AirdropLeaf(index, account, amount), proof) {
		return ErrBadProof
	}
	d.claimed.Set(index)
	return nil
}

// AirdropLeaf returns the leaf hash for one distribution entry.
//
// The bytes hashed are, in order: index as 8 big-endian bytes, the length of
// the address as 2 big-endian bytes, the address, and amount as 8 big-endian
// bytes two's complement. Length-prefixing the address is what keeps the
// encoding unambiguous. The result is passed through [LeafHash]. An off-chain
// generator must produce exactly these bytes.
func AirdropLeaf(index uint64, account address, amount int64) []byte {
	addr := []byte(account.String())
	buf := make([]byte, 0, 8+2+len(addr)+8)

	var n8 [8]byte
	binary.BigEndian.PutUint64(n8[:], index)
	buf = append(buf, n8[:]...)

	var n2 [2]byte
	binary.BigEndian.PutUint16(n2[:], uint16(len(addr)))
	buf = append(buf, n2[:]...)
	buf = append(buf, addr...)

	binary.BigEndian.PutUint64(n8[:], uint64(amount))
	buf = append(buf, n8[:]...)

	return LeafHash(buf)
}
