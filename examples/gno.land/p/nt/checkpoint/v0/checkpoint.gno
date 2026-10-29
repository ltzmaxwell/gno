package checkpoint

import "errors"

var (
	// ErrHeightWentBackwards is returned when a push names a height before
	// the last one recorded. A History is append-only.
	ErrHeightWentBackwards = errors.New("checkpoint: height went backwards")
	// ErrNegativeHeight is returned for a height below zero.
	ErrNegativeHeight = errors.New("checkpoint: negative height")
)

// Entry is one recorded change: value held from Height until the next entry.
type Entry struct {
	Height int64
	Value  int64
}

// History is an append-only record of a value over time.
//
// The zero value is an empty History whose value is 0 at every height.
type History struct {
	entries []Entry
}

// NewHistory returns an empty History.
func NewHistory() *History { return &History{} }

// Len returns the number of entries.
func (h *History) Len() int {
	if h == nil {
		return 0
	}
	return len(h.entries)
}

// At returns the value as of height: the most recent entry at or before it,
// or 0 when the history had not started.
func (h *History) At(height int64) int64 {
	if h == nil || len(h.entries) == 0 {
		return 0
	}
	// Last entry first: a lookup at the current height is the common case.
	if height >= h.entries[len(h.entries)-1].Height {
		return h.entries[len(h.entries)-1].Value
	}
	if height < h.entries[0].Height {
		return 0
	}
	// Binary search for the last entry with Height <= height.
	lo, hi := 0, len(h.entries)-1
	for lo < hi {
		mid := (lo + hi + 1) / 2
		if h.entries[mid].Height <= height {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	return h.entries[lo].Value
}

// Latest returns the current value, or 0 when the history is empty.
func (h *History) Latest() int64 {
	if h == nil || len(h.entries) == 0 {
		return 0
	}
	return h.entries[len(h.entries)-1].Value
}

// LatestHeight returns the height of the last entry and whether there is one.
func (h *History) LatestHeight() (int64, bool) {
	if h == nil || len(h.entries) == 0 {
		return 0, false
	}
	return h.entries[len(h.entries)-1].Height, true
}

// Entry returns the entry at position i.
func (h *History) Entry(i int) (Entry, bool) {
	if h == nil || i < 0 || i >= len(h.entries) {
		return Entry{}, false
	}
	return h.entries[i], true
}

// Push records value as of height.
//
// Pushing at the height of the last entry overwrites it rather than appending,
// so several changes in one block cost one entry and leave no intermediate
// state visible to a later lookup. Pushing an unchanged value is a no-op.
func (h *History) Push(height, value int64) error {
	if height < 0 {
		return ErrNegativeHeight
	}
	if n := len(h.entries); n > 0 {
		last := h.entries[n-1]
		if height < last.Height {
			return ErrHeightWentBackwards
		}
		if last.Value == value {
			return nil
		}
		if height == last.Height {
			h.entries[n-1].Value = value
			return nil
		}
	} else if value == 0 {
		// An opening zero says nothing At() does not already say.
		return nil
	}
	h.entries = append(h.entries, Entry{Height: height, Value: value})
	return nil
}

// canPush reports the error Push would return for height, without recording
// anything. Callers that mutate several histories at once check them all
// before touching any, so a rejected update leaves nothing half-applied.
func (h *History) canPush(height int64) error {
	if height < 0 {
		return ErrNegativeHeight
	}
	if n := len(h.entries); n > 0 && height < h.entries[n-1].Height {
		return ErrHeightWentBackwards
	}
	return nil
}

// Add records the value at height moved by delta. It returns the new value.
func (h *History) Add(height, delta int64) (int64, error) {
	next := h.Latest() + delta
	if err := h.Push(height, next); err != nil {
		return h.Latest(), err
	}
	return next, nil
}
