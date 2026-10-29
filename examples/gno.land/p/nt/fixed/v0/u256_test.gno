package fixed

import (
	"math/bits"
	"testing"
)

func TestMul128(t *testing.T) {
	tests := []struct {
		name                   string
		aHi, aLo, bHi, bLo     uint64
		want                   u256
	}{
		{"zero", 0, 0, 12345, 678, u256{0, 0, 0, 0}},
		{"small", 0, 7, 0, 6, u256{42, 0, 0, 0}},
		{"carry into w1", 0, 1 << 32, 0, 1 << 32, u256{0, 1, 0, 0}},
		{"64x64 full", 0, ^uint64(0), 0, ^uint64(0), u256{1, ^uint64(0) - 1, 0, 0}},
		{
			"128x128 max",
			^uint64(0), ^uint64(0), ^uint64(0), ^uint64(0),
			// (2**128-1)**2 == 2**256 - 2**129 + 1
			u256{1, 0, ^uint64(0) - 1, ^uint64(0)},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := mul128(tt.aHi, tt.aLo, tt.bHi, tt.bLo)
			if got != tt.want {
				t.Errorf("mul128 = %v, want %v", got, tt.want)
			}
		})
	}
}

// TestMul128Commutative cross-checks the schoolbook product against itself
// with the operands swapped, which exercises every carry path.
func TestMul128Commutative(t *testing.T) {
	vals := [][2]uint64{
		{0, 1}, {0, ^uint64(0)}, {1, 0}, {3, 17}, {^uint64(0), 0},
		{1 << 63, 1 << 63}, {12345678901234567, 98765432109876543},
	}
	for _, a := range vals {
		for _, b := range vals {
			x := mul128(a[0], a[1], b[0], b[1])
			y := mul128(b[0], b[1], a[0], a[1])
			if x != y {
				t.Fatalf("mul128(%v,%v) = %v but mul128(%v,%v) = %v", a, b, x, b, a, y)
			}
		}
	}
}

func TestDivmod256by128FastPath(t *testing.T) {
	// 7e18 / 1e18 == 7 remainder 0.
	n := mul128(0, 7, 0, scale)
	qHi, qLo, rHi, rLo := divmod256by128(n, 0, scale)
	if qHi != 0 || qLo != 7 || rHi != 0 || rLo != 0 {
		t.Fatalf("got q=(%d,%d) r=(%d,%d), want q=(0,7) r=(0,0)", qHi, qLo, rHi, rLo)
	}

	// 7e18+3 / 1e18 == 7 remainder 3.
	n2 := n
	n2[0] += 3
	_, qLo, _, rLo = divmod256by128(n2, 0, scale)
	if qLo != 7 || rLo != 3 {
		t.Fatalf("got q=%d r=%d, want q=7 r=3", qLo, rLo)
	}
}

func TestDivmod256by128SlowPath(t *testing.T) {
	// A divisor wider than 64 bits takes the shift-subtract path. Build
	// n = d*q + r with known d, q and r, then recover q and r.
	dHi, dLo := uint64(5), uint64(123456789)
	qHi, qLo := uint64(0), uint64(999999999999)
	r := uint64(42)

	n := mul128(dHi, dLo, qHi, qLo)
	n = n.add(u256{r, 0, 0, 0})

	gotQHi, gotQLo, gotRHi, gotRLo := divmod256by128(n, dHi, dLo)
	if gotQHi != qHi || gotQLo != qLo {
		t.Errorf("quotient = (%d,%d), want (%d,%d)", gotQHi, gotQLo, qHi, qLo)
	}
	if gotRHi != 0 || gotRLo != r {
		t.Errorf("remainder = (%d,%d), want (0,%d)", gotRHi, gotRLo, r)
	}
}

func TestDivmod256by128SmallerThanDivisor(t *testing.T) {
	qHi, qLo, rHi, rLo := divmod256by128(u256{9, 1, 0, 0}, 5, 0)
	if qHi != 0 || qLo != 0 {
		t.Errorf("quotient = (%d,%d), want (0,0)", qHi, qLo)
	}
	if rHi != 1 || rLo != 9 {
		t.Errorf("remainder = (%d,%d), want (1,9)", rHi, rLo)
	}
}

func TestDivmod256by128Panics(t *testing.T) {
	assertPanics(t, errDivByZero, func() {
		divmod256by128(u256{1, 0, 0, 0}, 0, 0)
	})
	assertPanics(t, errOverflow, func() {
		// 2**192 / 1 does not fit in 128 bits.
		divmod256by128(u256{0, 0, 0, 1}, 0, 1)
	})
}

func TestIsqrt256(t *testing.T) {
	tests := []struct {
		n        u256
		wantHi   uint64
		wantLo   uint64
	}{
		{u256{0, 0, 0, 0}, 0, 0},
		{u256{1, 0, 0, 0}, 0, 1},
		{u256{2, 0, 0, 0}, 0, 1},
		{u256{3, 0, 0, 0}, 0, 1},
		{u256{4, 0, 0, 0}, 0, 2},
		{u256{99, 0, 0, 0}, 0, 9},
		{u256{100, 0, 0, 0}, 0, 10},
		{u256{0, 1, 0, 0}, 0, 1 << 32},            // 2**64
		{u256{0, 0, 1, 0}, 1, 0},                  // 2**128
		{u256{^uint64(0), ^uint64(0), ^uint64(0), ^uint64(0)}, ^uint64(0), ^uint64(0)},
	}
	for _, tt := range tests {
		hi, lo := isqrt256(tt.n)
		if hi != tt.wantHi || lo != tt.wantLo {
			t.Errorf("isqrt256(%v) = (%d,%d), want (%d,%d)", tt.n, hi, lo, tt.wantHi, tt.wantLo)
		}
	}
}

// TestIsqrt256Invariant checks r*r <= n < (r+1)*(r+1) on a spread of inputs.
func TestIsqrt256Invariant(t *testing.T) {
	ns := []u256{
		{1, 0, 0, 0}, {5, 0, 0, 0}, {1 << 40, 0, 0, 0},
		{0, 3, 0, 0}, {7, 11, 0, 0}, {^uint64(0), 1 << 20, 0, 0},
		{1, 2, 3, 0},
	}
	for _, n := range ns {
		hi, lo := isqrt256(n)
		sq := mul128(hi, lo, hi, lo)
		if sq.cmp(n) > 0 {
			t.Errorf("isqrt256(%v)**2 = %v exceeds n", n, sq)
		}
		nhi, nlo, carry := add128(hi, lo, 0, 1)
		if carry != 0 {
			continue
		}
		next := mul128(nhi, nlo, nhi, nlo)
		if next.cmp(n) <= 0 {
			t.Errorf("isqrt256(%v) is too small: (r+1)**2 = %v still fits", n, next)
		}
	}
}

func TestU256Shl(t *testing.T) {
	one := u256{1, 0, 0, 0}
	if got := one.shl(0); got != one {
		t.Errorf("shl(0) = %v, want %v", got, one)
	}
	if got := one.shl(64); got != (u256{0, 1, 0, 0}) {
		t.Errorf("shl(64) = %v", got)
	}
	if got := one.shl(65); got != (u256{0, 2, 0, 0}) {
		t.Errorf("shl(65) = %v", got)
	}
	if got := one.shl(255); got != (u256{0, 0, 0, 1 << 63}) {
		t.Errorf("shl(255) = %v", got)
	}
	if got := one.shl(256); !got.isZero() {
		t.Errorf("shl(256) = %v, want zero", got)
	}
}

func TestU256ShiftRoundTrip(t *testing.T) {
	n := u256{0x0123456789abcdef, 0xfedcba9876543210, 7, 1 << 62}
	for s := 1; s < 200; s++ {
		shifted := n.shl(s)
		back := shifted
		for i := 0; i < s; i++ {
			back = back.shr1()
		}
		// Shifting left then right drops the top s bits of n.
		want := n
		for i := 0; i < s; i++ {
			want = want.shl1()
		}
		for i := 0; i < s; i++ {
			want = want.shr1()
		}
		if back != want {
			t.Fatalf("shift %d: got %v, want %v", s, back, want)
		}
	}
}

func TestU256BitLen(t *testing.T) {
	if got := (u256{}).bitLen(); got != 0 {
		t.Errorf("bitLen(0) = %d, want 0", got)
	}
	for s := 0; s < 256; s++ {
		n := u256{1, 0, 0, 0}.shl(s)
		if got := n.bitLen(); got != s+1 {
			t.Errorf("bitLen(1<<%d) = %d, want %d", s, got, s+1)
		}
	}
}

func TestMulAdd128(t *testing.T) {
	hi, lo, ok := mulAdd128(0, 123, 10, 4)
	if !ok || hi != 0 || lo != 1234 {
		t.Errorf("mulAdd128 = (%d,%d,%v), want (0,1234,true)", hi, lo, ok)
	}
	// Overflowing the high word must be reported, not wrapped.
	if _, _, ok := mulAdd128(^uint64(0), ^uint64(0), 10, 0); ok {
		t.Error("mulAdd128 overflow not detected")
	}
	// The carry out of the low word must reach the high word.
	hi, lo, ok = mulAdd128(0, ^uint64(0), 1, 1)
	if !ok || hi != 1 || lo != 0 {
		t.Errorf("mulAdd128 carry = (%d,%d,%v), want (1,0,true)", hi, lo, ok)
	}
}

func TestBitsDiv64Assumption(t *testing.T) {
	// divmod256by128 and u128Decimal both rely on Div64 accepting a zero
	// high word for any divisor.
	q, r := bits.Div64(0, ^uint64(0), chunk)
	if q != 1 || r != ^uint64(0)-chunk {
		t.Errorf("Div64 = (%d,%d)", q, r)
	}
}
