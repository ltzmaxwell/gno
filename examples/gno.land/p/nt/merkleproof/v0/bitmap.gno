package merkleproof

// Bitmap tracks which indices of a committed list have been used, packed 64
// to a word so that a dense claim range costs one map entry per 64 claims.
//
// Only Get and Set are offered: nothing iterates it, so the map's undefined
// iteration order never reaches consensus.
type Bitmap struct {
	words map[uint64]uint64
	count uint64
}

// NewBitmap returns an empty Bitmap.
func NewBitmap() *Bitmap {
	return &Bitmap{words: make(map[uint64]uint64)}
}

// Get reports whether index is set.
func (b *Bitmap) Get(index uint64) bool {
	if b == nil || b.words == nil {
		return false
	}
	return b.words[index/64]&(1<<(index%64)) != 0
}

// Set marks index and reports whether this call was the one that set it. A
// second Set of the same index returns false and changes nothing, which is
// the check a claim wants.
func (b *Bitmap) Set(index uint64) bool {
	if b.words == nil {
		b.words = make(map[uint64]uint64)
	}
	word, bit := index/64, uint64(1)<<(index%64)
	if b.words[word]&bit != 0 {
		return false
	}
	b.words[word] |= bit
	b.count++
	return true
}

// Count returns how many distinct indices have been set.
func (b *Bitmap) Count() uint64 {
	if b == nil {
		return 0
	}
	return b.count
}
