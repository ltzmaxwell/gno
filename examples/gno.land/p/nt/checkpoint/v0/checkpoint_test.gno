package checkpoint

import "testing"

func TestEmptyHistory(t *testing.T) {
	var h History
	if h.Len() != 0 || h.Latest() != 0 {
		t.Error("zero value is not empty")
	}
	for _, at := range []int64{0, 1, 1 << 40} {
		if got := h.At(at); got != 0 {
			t.Errorf("At(%d) = %d, want 0", at, got)
		}
	}
	if _, ok := h.LatestHeight(); ok {
		t.Error("empty history reported a latest height")
	}
	if _, ok := h.Entry(0); ok {
		t.Error("empty history returned an entry")
	}
}

func TestNilHistoryIsReadable(t *testing.T) {
	var h *History
	if h.Len() != 0 || h.Latest() != 0 || h.At(5) != 0 {
		t.Error("nil history is not readable as empty")
	}
	if _, ok := h.LatestHeight(); ok {
		t.Error("nil history reported a latest height")
	}
}

func TestPushAndLookup(t *testing.T) {
	h := NewHistory()
	mustPush(t, h, 10, 100)
	mustPush(t, h, 20, 250)
	mustPush(t, h, 30, 7)

	tests := []struct{ at, want int64 }{
		{0, 0}, {9, 0},
		{10, 100}, {11, 100}, {19, 100},
		{20, 250}, {29, 250},
		{30, 7}, {31, 7}, {1 << 40, 7},
	}
	for _, tt := range tests {
		if got := h.At(tt.at); got != tt.want {
			t.Errorf("At(%d) = %d, want %d", tt.at, got, tt.want)
		}
	}
	if h.Len() != 3 {
		t.Errorf("Len = %d, want 3", h.Len())
	}
	if got, ok := h.LatestHeight(); !ok || got != 30 {
		t.Errorf("LatestHeight = (%d,%v)", got, ok)
	}
	if e, ok := h.Entry(1); !ok || e.Height != 20 || e.Value != 250 {
		t.Errorf("Entry(1) = %v, %v", e, ok)
	}
}

// TestSameHeightOverwrites keeps several changes in one block from leaving an
// intermediate value a later lookup could read.
func TestSameHeightOverwrites(t *testing.T) {
	h := NewHistory()
	mustPush(t, h, 10, 100)
	mustPush(t, h, 20, 200)
	mustPush(t, h, 20, 300)
	mustPush(t, h, 20, 400)

	if h.Len() != 2 {
		t.Errorf("Len = %d, want 2 (one entry per height)", h.Len())
	}
	if got := h.At(20); got != 400 {
		t.Errorf("At(20) = %d, want 400", got)
	}
	if got := h.At(19); got != 100 {
		t.Errorf("At(19) = %d, want 100", got)
	}
}

func TestPushSkipsRedundantEntries(t *testing.T) {
	h := NewHistory()
	mustPush(t, h, 5, 0) // an opening zero says nothing
	if h.Len() != 0 {
		t.Errorf("opening zero recorded: Len = %d", h.Len())
	}
	mustPush(t, h, 10, 50)
	mustPush(t, h, 20, 50) // unchanged
	if h.Len() != 1 {
		t.Errorf("unchanged value recorded: Len = %d", h.Len())
	}
	mustPush(t, h, 30, 0) // a later zero is a real change
	if h.Len() != 2 {
		t.Errorf("Len = %d, want 2", h.Len())
	}
	if got := h.At(30); got != 0 {
		t.Errorf("At(30) = %d, want 0", got)
	}
}

func TestPushRejectsBadHeights(t *testing.T) {
	h := NewHistory()
	mustPush(t, h, 10, 1)
	if err := h.Push(9, 2); err != ErrHeightWentBackwards {
		t.Errorf("backwards push = %v, want ErrHeightWentBackwards", err)
	}
	if err := h.Push(-1, 2); err != ErrNegativeHeight {
		t.Errorf("negative push = %v, want ErrNegativeHeight", err)
	}
	if h.Len() != 1 || h.Latest() != 1 {
		t.Error("a rejected push changed the history")
	}
}

func TestAdd(t *testing.T) {
	h := NewHistory()
	if v, err := h.Add(10, 5); err != nil || v != 5 {
		t.Errorf("Add = (%d,%v)", v, err)
	}
	if v, err := h.Add(20, -3); err != nil || v != 2 {
		t.Errorf("Add = (%d,%v)", v, err)
	}
	if got := h.At(15); got != 5 {
		t.Errorf("At(15) = %d, want 5", got)
	}
	if _, err := h.Add(5, 1); err != ErrHeightWentBackwards {
		t.Errorf("backwards Add = %v", err)
	}
}

// TestBinarySearchMatchesLinearScan exercises the search over a history long
// enough for the midpoints to matter.
func TestBinarySearchMatchesLinearScan(t *testing.T) {
	h := NewHistory()
	const n = 200
	for i := int64(0); i < n; i++ {
		mustPush(t, h, i*3, (i+1)*11)
	}
	for at := int64(-1); at <= n*3+2; at++ {
		want := int64(0)
		for i := 0; i < h.Len(); i++ {
			e, _ := h.Entry(i)
			if e.Height <= at {
				want = e.Value
			}
		}
		if got := h.At(at); got != want {
			t.Fatalf("At(%d) = %d, want %d", at, got, want)
		}
	}
}

func mustPush(t *testing.T, h *History, height, value int64) {
	t.Helper()
	if err := h.Push(height, value); err != nil {
		t.Fatalf("Push(%d,%d): %v", height, value, err)
	}
}
