package fixed

import (
	"fmt"
	"strings"
	"testing"
)

// assertPanics runs fn and fails unless it panics with a value whose text
// contains want.
func assertPanics(t *testing.T, want string, fn func()) {
	t.Helper()
	defer func() {
		r := recover()
		if r == nil {
			t.Errorf("expected a panic containing %q, got none", want)
			return
		}
		if got := fmt.Sprint(r); !strings.Contains(got, want) {
			t.Errorf("panic = %q, want it to contain %q", got, want)
		}
	}()
	fn()
}

// maxDec is the largest representable value, 2**128-1 units.
func maxDec() Dec { return Dec{hi: ^uint64(0), lo: ^uint64(0)} }

func TestConstructors(t *testing.T) {
	if !Zero().IsZero() {
		t.Error("Zero is not zero")
	}
	if got := One().String(); got != "1" {
		t.Errorf("One = %s, want 1", got)
	}
	if got := Smallest().String(); got != "0.000000000000000001" {
		t.Errorf("Smallest = %s", got)
	}
	if got := FromInt64(-7).String(); got != "-7" {
		t.Errorf("FromInt64(-7) = %s", got)
	}
	if got := FromUint64(0).String(); got != "0" {
		t.Errorf("FromUint64(0) = %s", got)
	}
	if got := NewFrac(1, 4).String(); got != "0.25" {
		t.Errorf("NewFrac(1,4) = %s", got)
	}
	// Negating the most negative int64 must not wrap.
	if got := FromInt64(-1 << 63).String(); got != "-9223372036854775808" {
		t.Errorf("FromInt64(MinInt64) = %s", got)
	}
}

// TestZeroIsCanonical is what lets Dec be compared with == and used as a map
// key: there must be no negative zero.
func TestZeroIsCanonical(t *testing.T) {
	cases := []Dec{
		Zero(),
		MustParse("-0"),
		MustParse("-0.000"),
		FromInt64(0).Neg(),
		FromInt64(5).Sub(FromInt64(5)),
		MustParse("-1").Mul(Zero()),
	}
	for i, d := range cases {
		if d != (Dec{}) {
			t.Errorf("case %d: %#v is not the canonical zero", i, d)
		}
		if d.Sign() != 0 || d.String() != "0" {
			t.Errorf("case %d: sign=%d string=%s", i, d.Sign(), d.String())
		}
	}
}

func TestUnitsRoundTrip(t *testing.T) {
	d := MustParse("-1.5")
	neg, hi, lo := d.Units()
	if got := FromUnits(neg, hi, lo); got != d {
		t.Errorf("round trip = %v, want %v", got, d)
	}
	if !neg || hi != 0 || lo != 1_500_000_000_000_000_000 {
		t.Errorf("Units = (%v,%d,%d), want (true,0,1500000000000000000)", neg, hi, lo)
	}

	// A value past 2**64 units exercises the high word.
	big := MustParse("123.456")
	neg, hi, lo = big.Units()
	if neg || hi != 6 || lo != 12_775_535_557_742_690_304 {
		t.Errorf("Units(123.456) = (%v,%d,%d)", neg, hi, lo)
	}
	if got := FromUnits(neg, hi, lo); got != big {
		t.Errorf("round trip of 123.456 failed")
	}
}

func TestSignAndPredicates(t *testing.T) {
	tests := []struct {
		s                     string
		sign                  int
		zero, negv, pos, intg bool
	}{
		{"0", 0, true, false, false, true},
		{"1", 1, false, false, true, true},
		{"-1", -1, false, true, false, true},
		{"0.5", 1, false, false, true, false},
		{"-0.000000000000000001", -1, false, true, false, false},
		{"100", 1, false, false, true, true},
	}
	for _, tt := range tests {
		d := MustParse(tt.s)
		if d.Sign() != tt.sign {
			t.Errorf("%s: Sign = %d, want %d", tt.s, d.Sign(), tt.sign)
		}
		if d.IsZero() != tt.zero {
			t.Errorf("%s: IsZero = %v", tt.s, d.IsZero())
		}
		if d.IsNegative() != tt.negv {
			t.Errorf("%s: IsNegative = %v", tt.s, d.IsNegative())
		}
		if d.IsPositive() != tt.pos {
			t.Errorf("%s: IsPositive = %v", tt.s, d.IsPositive())
		}
		if d.IsInteger() != tt.intg {
			t.Errorf("%s: IsInteger = %v", tt.s, d.IsInteger())
		}
	}
}

func TestCompare(t *testing.T) {
	tests := []struct {
		a, b string
		want int
	}{
		{"0", "0", 0},
		{"1", "1", 0},
		{"-1", "-1", 0},
		{"1", "2", -1},
		{"2", "1", 1},
		{"-2", "-1", -1},
		{"-1", "-2", 1},
		{"-1", "1", -1},
		{"0", "-0.000000000000000001", 1},
		{"0.1", "0.10", 0},
		{"340282366920938463463.374607431768211455", "1", 1},
	}
	for _, tt := range tests {
		a, b := MustParse(tt.a), MustParse(tt.b)
		if got := a.Cmp(b); got != tt.want {
			t.Errorf("%s.Cmp(%s) = %d, want %d", tt.a, tt.b, got, tt.want)
		}
		if got := a.Equal(b); got != (tt.want == 0) {
			t.Errorf("%s.Equal(%s) = %v", tt.a, tt.b, got)
		}
		if got := a.Lt(b); got != (tt.want < 0) {
			t.Errorf("%s.Lt(%s) = %v", tt.a, tt.b, got)
		}
		if got := a.Gte(b); got != (tt.want >= 0) {
			t.Errorf("%s.Gte(%s) = %v", tt.a, tt.b, got)
		}
		if tt.want < 0 && a.Min(b) != a {
			t.Errorf("%s.Min(%s) wrong", tt.a, tt.b)
		}
		if tt.want > 0 && a.Max(b) != a {
			t.Errorf("%s.Max(%s) wrong", tt.a, tt.b)
		}
	}
}

func TestAddSub(t *testing.T) {
	tests := []struct {
		a, b, sum, diff string
	}{
		{"0", "0", "0", "0"},
		{"1", "2", "3", "-1"},
		{"2", "1", "3", "1"},
		{"-1", "-2", "-3", "1"},
		{"-1", "2", "1", "-3"},
		{"1", "-2", "-1", "3"},
		{"5", "-5", "0", "10"},
		{"0.1", "0.2", "0.3", "-0.1"},
		{
			"0.000000000000000001", "0.000000000000000002",
			"0.000000000000000003", "-0.000000000000000001",
		},
	}
	for _, tt := range tests {
		a, b := MustParse(tt.a), MustParse(tt.b)
		if got := a.Add(b).String(); got != tt.sum {
			t.Errorf("%s + %s = %s, want %s", tt.a, tt.b, got, tt.sum)
		}
		if got := a.Sub(b).String(); got != tt.diff {
			t.Errorf("%s - %s = %s, want %s", tt.a, tt.b, got, tt.diff)
		}
	}
}

// TestAddIsExactUnlikeFloat is the reason this package exists: ten tenths are
// exactly one, and 0.1+0.2 is exactly 0.3.
func TestAddIsExactUnlikeFloat(t *testing.T) {
	sum := Zero()
	tenth := MustParse("0.1")
	for i := 0; i < 10; i++ {
		sum = sum.Add(tenth)
	}
	if !sum.Equal(One()) {
		t.Errorf("ten tenths = %s, want 1", sum)
	}
	if got := MustParse("0.1").Add(MustParse("0.2")); !got.Equal(MustParse("0.3")) {
		t.Errorf("0.1+0.2 = %s, want 0.3", got)
	}
}

func TestAddOverflowPanics(t *testing.T) {
	assertPanics(t, errOverflow, func() {
		maxDec().Add(Smallest())
	})
	assertPanics(t, errOverflow, func() {
		maxDec().Neg().Sub(Smallest())
	})
	// The same magnitudes with opposite signs must not panic.
	if got := maxDec().Add(maxDec().Neg()); !got.IsZero() {
		t.Errorf("max + -max = %s, want 0", got)
	}
}

func TestMul(t *testing.T) {
	tests := []struct {
		a, b, want string
	}{
		{"0", "5", "0"},
		{"1", "1", "1"},
		{"2", "3", "6"},
		{"-2", "3", "-6"},
		{"-2", "-3", "6"},
		{"1.5", "1.5", "2.25"},
		{"0.000000001", "0.000000001", "0.000000000000000001"},
		{"1000000000", "1000000000", "1000000000000000000"},
		{"0.1", "0.2", "0.02"},
	}
	for _, tt := range tests {
		got := MustParse(tt.a).Mul(MustParse(tt.b)).String()
		if got != tt.want {
			t.Errorf("%s * %s = %s, want %s", tt.a, tt.b, got, tt.want)
		}
	}
}

// TestMulRoundingModes pins the behaviour at exactly one half of the last
// representable digit, where the modes disagree.
func TestMulRoundingModes(t *testing.T) {
	unit := Smallest()            // 1e-18
	half := MustParse("0.5")      // product is exactly 5e-19, a tie
	threeHalves := MustParse("1.5") // product is 1.5e-18, a tie above 1

	tests := []struct {
		name       string
		a, b       Dec
		mode       RoundingMode
		want       string
	}{
		{"half-even ties to even (down)", unit, half, RoundHalfEven, "0"},
		{"half-up ties away", unit, half, RoundHalfUp, "0.000000000000000001"},
		{"toward zero truncates", unit, half, RoundTowardZero, "0"},
		{"away from zero", unit, half, RoundAwayFromZero, "0.000000000000000001"},
		{"half-even ties to even (up)", unit, threeHalves, RoundHalfEven, "0.000000000000000002"},
		{"half-up at 1.5 units", unit, threeHalves, RoundHalfUp, "0.000000000000000002"},
		{"toward zero at 1.5 units", unit, threeHalves, RoundTowardZero, "0.000000000000000001"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.a.MulRound(tt.b, tt.mode).String(); got != tt.want {
				t.Errorf("got %s, want %s", got, tt.want)
			}
		})
	}

	// Rounding acts on the magnitude, so the negative case mirrors exactly.
	if got := unit.Neg().MulRound(half, RoundAwayFromZero).String(); got != "-0.000000000000000001" {
		t.Errorf("negative away-from-zero = %s", got)
	}
}

func TestDiv(t *testing.T) {
	tests := []struct {
		a, b, want string
	}{
		{"6", "3", "2"},
		{"-6", "3", "-2"},
		{"-6", "-3", "2"},
		{"1", "3", "0.333333333333333333"},
		{"2", "3", "0.666666666666666667"},
		{"1", "8", "0.125"},
		{"0", "5", "0"},
		{"1", "0.000000000000000001", "1000000000000000000"},
		{"0.000000000000000001", "2", "0"},
		{"0.000000000000000003", "2", "0.000000000000000002"},
	}
	for _, tt := range tests {
		got := MustParse(tt.a).Div(MustParse(tt.b)).String()
		if got != tt.want {
			t.Errorf("%s / %s = %s, want %s", tt.a, tt.b, got, tt.want)
		}
	}
}

func TestDivByZeroPanics(t *testing.T) {
	assertPanics(t, errDivByZero, func() { One().Div(Zero()) })
	assertPanics(t, errDivByZero, func() { Zero().Div(Zero()) })
	assertPanics(t, errDivByZero, func() { One().MulDiv(One(), Zero(), RoundHalfEven) })
	assertPanics(t, errDivByZero, func() { NewFrac(1, 0) })
}

func TestDivOverflowPanics(t *testing.T) {
	assertPanics(t, errOverflow, func() {
		maxDec().Div(Smallest())
	})
}

// TestMulDivRoundsOnce is the whole point of MulDiv: the intermediate product
// keeps 256 bits, so a value that would vanish in a separate Mul survives.
func TestMulDivRoundsOnce(t *testing.T) {
	u := Smallest()

	// u*u underflows to zero on its own, so the two-step form loses it.
	if got := u.Mul(u); !got.IsZero() {
		t.Fatalf("u*u = %s, want 0 (the lossy step)", got)
	}
	if got := u.Mul(u).Div(u); !got.IsZero() {
		t.Fatalf("(u*u)/u = %s, want 0", got)
	}
	// One rounding step gives the exact answer instead.
	if got := u.MulDiv(u, u, RoundHalfEven); !got.Equal(u) {
		t.Errorf("u.MulDiv(u,u) = %s, want %s", got, u)
	}

	// A fee calculation that is exact in MulDiv and not in Mul-then-Div.
	amount := MustParse("1")
	num := MustParse("1")
	den := MustParse("3")
	once := amount.MulDiv(num, den, RoundTowardZero)
	if got := once.String(); got != "0.333333333333333333" {
		t.Errorf("MulDiv = %s", got)
	}

	// Signs multiply through all three operands.
	neg := MustParse("-2").MulDiv(MustParse("3"), MustParse("-4"), RoundHalfEven)
	if got := neg.String(); got != "1.5" {
		t.Errorf("(-2*3)/-4 = %s, want 1.5", got)
	}
	neg = MustParse("-2").MulDiv(MustParse("3"), MustParse("4"), RoundHalfEven)
	if got := neg.String(); got != "-1.5" {
		t.Errorf("(-2*3)/4 = %s, want -1.5", got)
	}
}

func TestPow(t *testing.T) {
	tests := []struct {
		base string
		n    uint64
		want string
	}{
		{"0", 0, "1"},
		{"5", 0, "1"},
		{"5", 1, "5"},
		{"2", 10, "1024"},
		{"1.1", 10, "2.5937424601"},
		{"-2", 3, "-8"},
		{"-2", 4, "16"},
		{"0.5", 3, "0.125"},
		{"0", 5, "0"},
	}
	for _, tt := range tests {
		got := MustParse(tt.base).Pow(tt.n).String()
		if got != tt.want {
			t.Errorf("%s ** %d = %s, want %s", tt.base, tt.n, got, tt.want)
		}
	}
}

func TestSqrt(t *testing.T) {
	tests := []struct{ in, want string }{
		{"0", "0"},
		{"1", "1"},
		{"4", "2"},
		{"0.25", "0.5"},
		{"2", "1.414213562373095048"},
		{"1000000", "1000"},
		{"0.000000000000000001", "0.000000001"},
	}
	for _, tt := range tests {
		got := MustParse(tt.in).Sqrt().String()
		if got != tt.want {
			t.Errorf("sqrt(%s) = %s, want %s", tt.in, got, tt.want)
		}
	}

	// Truncation, never overshoot. Compared in 10**-36 units so that the
	// check itself does not round: r**2 <= x < (r+1)**2.
	for _, s := range []string{"2", "3", "7.5", "99999.123456789", "0.3"} {
		x := MustParse(s)
		r := x.Sqrt()
		m := mul128(x.hi, x.lo, 0, scale)
		if mul128(r.hi, r.lo, r.hi, r.lo).cmp(m) > 0 {
			t.Errorf("sqrt(%s)=%s squares above the input", s, r)
		}
		nhi, nlo, _ := add128(r.hi, r.lo, 0, 1)
		if mul128(nhi, nlo, nhi, nlo).cmp(m) <= 0 {
			t.Errorf("sqrt(%s)=%s is one unit too small", s, r)
		}
	}

	assertPanics(t, errNegSqrt, func() { MustParse("-1").Sqrt() })
}

func TestRoundTo(t *testing.T) {
	tests := []struct {
		in     string
		places int
		mode   RoundingMode
		want   string
	}{
		{"1.2345", 2, RoundHalfEven, "1.23"},
		{"1.2355", 2, RoundHalfEven, "1.24"},
		{"1.225", 2, RoundHalfEven, "1.22"},
		{"1.235", 2, RoundHalfEven, "1.24"},
		{"1.225", 2, RoundHalfUp, "1.23"},
		{"-1.225", 2, RoundHalfUp, "-1.23"},
		{"1.999", 0, RoundTowardZero, "1"},
		{"1.001", 0, RoundAwayFromZero, "2"},
		{"-1.001", 0, RoundAwayFromZero, "-2"},
		{"5", 0, RoundAwayFromZero, "5"},
		{"1.23456789", 18, RoundHalfEven, "1.23456789"},
	}
	for _, tt := range tests {
		got := MustParse(tt.in).RoundTo(tt.places, tt.mode).String()
		if got != tt.want {
			t.Errorf("RoundTo(%s, %d) = %s, want %s", tt.in, tt.places, got, tt.want)
		}
	}

	assertPanics(t, errPlaces, func() { One().RoundTo(-1, RoundHalfEven) })
	assertPanics(t, errPlaces, func() { One().RoundTo(19, RoundHalfEven) })
	assertPanics(t, errMode, func() { One().MulRound(One(), RoundingMode(9)) })
}

func TestTruncateFloorCeil(t *testing.T) {
	tests := []struct{ in, trunc, floor, ceil string }{
		{"1.5", "1", "1", "2"},
		{"-1.5", "-1", "-2", "-1"},
		{"2", "2", "2", "2"},
		{"-2", "-2", "-2", "-2"},
		{"0.000000000000000001", "0", "0", "1"},
		{"-0.000000000000000001", "0", "-1", "0"},
	}
	for _, tt := range tests {
		d := MustParse(tt.in)
		if got := d.Truncate().String(); got != tt.trunc {
			t.Errorf("Truncate(%s) = %s, want %s", tt.in, got, tt.trunc)
		}
		if got := d.Floor().String(); got != tt.floor {
			t.Errorf("Floor(%s) = %s, want %s", tt.in, got, tt.floor)
		}
		if got := d.Ceil().String(); got != tt.ceil {
			t.Errorf("Ceil(%s) = %s, want %s", tt.in, got, tt.ceil)
		}
	}
}

func TestTruncInt64(t *testing.T) {
	tests := []struct {
		in   string
		want int64
		ok   bool
	}{
		{"0", 0, true},
		{"1.9", 1, true},
		{"-1.9", -1, true},
		{"9223372036854775807", 1<<63 - 1, true},
		{"-9223372036854775808", -1 << 63, true},
		{"9223372036854775808", 0, false},
		{"-9223372036854775809", 0, false},
		{"340282366920938463463.374607431768211455", 0, false},
	}
	for _, tt := range tests {
		got, ok := MustParse(tt.in).TruncInt64()
		if ok != tt.ok || (ok && got != tt.want) {
			t.Errorf("TruncInt64(%s) = (%d,%v), want (%d,%v)", tt.in, got, ok, tt.want, tt.ok)
		}
	}
}

// TestRangeEnds exercises the extremes of the representable interval.
func TestRangeEnds(t *testing.T) {
	const maxStr = "340282366920938463463.374607431768211455"
	if got := maxDec().String(); got != maxStr {
		t.Errorf("max = %s, want %s", got, maxStr)
	}
	if got := MustParse(maxStr); got != maxDec() {
		t.Errorf("round trip of max failed")
	}
	if _, err := Parse("340282366920938463463.374607431768211456"); err == nil {
		t.Error("one unit past max parsed without error")
	}
	if got := maxDec().Neg().String(); got != "-"+maxStr {
		t.Errorf("min = %s", got)
	}

	// Rounding the maximum away from zero leaves the range: RoundTo keeps 18
	// digits and so must panic, while StringFixed only prints and must not.
	assertPanics(t, errOverflow, func() {
		maxDec().RoundTo(3, RoundHalfEven)
	})
	if got := maxDec().StringFixed(3); got != "340282366920938463463.375" {
		t.Errorf("StringFixed at max = %s", got)
	}
	if got := maxDec().StringFixed(0); got != "340282366920938463463" {
		t.Errorf("StringFixed(0) at max = %s", got)
	}
}
