package fixed

import "math/bits"

const (
	// Decimals is the number of fractional decimal digits every Dec carries.
	Decimals = 18

	// scale is 10**Decimals, the value of One.
	scale = 1_000_000_000_000_000_000
)

const (
	errOverflow  = "fixed: overflow"
	errDivByZero = "fixed: division by zero"
	errNegSqrt   = "fixed: square root of a negative number"
	errPlaces    = "fixed: places out of range"
	errMode      = "fixed: unknown rounding mode"
)

var pow10tab = [Decimals + 1]uint64{
	1,
	10,
	100,
	1_000,
	10_000,
	100_000,
	1_000_000,
	10_000_000,
	100_000_000,
	1_000_000_000,
	10_000_000_000,
	100_000_000_000,
	1_000_000_000_000,
	10_000_000_000_000,
	100_000_000_000_000,
	1_000_000_000_000_000,
	10_000_000_000_000_000,
	100_000_000_000_000_000,
	1_000_000_000_000_000_000,
}

// Dec is a signed decimal with exactly Decimals fractional digits, held as a
// sign and a 128-bit magnitude of 10**-18 units. The zero value is 0.
//
// Zero is always stored with a positive sign, so Dec is comparable with == and
// usable as a map key; [Dec.Equal] says the same thing more explicitly.
type Dec struct {
	neg bool
	hi  uint64
	lo  uint64
}

// RoundingMode selects what happens to the digits an operation cannot keep.
// Every mode acts on the magnitude, so RoundAwayFromZero moves -0.5 to -1 and
// 0.5 to 1.
type RoundingMode uint8

const (
	// RoundHalfEven rounds to the nearest value and breaks ties toward the
	// even digit. It is the default and the zero value.
	RoundHalfEven RoundingMode = iota
	// RoundHalfUp rounds to the nearest value and breaks ties away from zero.
	RoundHalfUp
	// RoundTowardZero discards the remainder.
	RoundTowardZero
	// RoundAwayFromZero rounds any inexact result away from zero.
	RoundAwayFromZero
)

// mkDec builds a Dec, forcing the sign of zero positive so that == works.
func mkDec(neg bool, hi, lo uint64) Dec {
	if hi == 0 && lo == 0 {
		return Dec{}
	}
	return Dec{neg: neg, hi: hi, lo: lo}
}

// Zero returns 0.
func Zero() Dec { return Dec{} }

// One returns 1.
func One() Dec { return Dec{lo: scale} }

// Smallest returns 10**-18, the smallest representable positive value.
func Smallest() Dec { return Dec{lo: 1} }

// FromInt64 returns i as a Dec.
func FromInt64(i int64) Dec {
	if i < 0 {
		// Negating math.MinInt64 overflows int64, so widen first.
		m := uint64(-(i + 1)) + 1
		hi, lo := bits.Mul64(m, scale)
		return mkDec(true, hi, lo)
	}
	hi, lo := bits.Mul64(uint64(i), scale)
	return mkDec(false, hi, lo)
}

// FromUint64 returns u as a Dec. It panics if u is too large to represent.
func FromUint64(u uint64) Dec {
	hi, lo := bits.Mul64(u, scale)
	return mkDec(false, hi, lo)
}

// FromUnits returns units * 10**-18, that is, a raw count of the smallest
// representable amount. Use it to lift an on-chain integer balance that is
// already scaled by 10**18.
func FromUnits(neg bool, hi, lo uint64) Dec {
	return mkDec(neg, hi, lo)
}

// Units returns the sign and the 128-bit magnitude in units of 10**-18, the
// inverse of [FromUnits].
func (d Dec) Units() (neg bool, hi, lo uint64) {
	return d.neg, d.hi, d.lo
}

// NewFrac returns num/denom rounded half to even. It panics if denom is zero.
func NewFrac(num, denom int64) Dec {
	return FromInt64(num).Div(FromInt64(denom))
}

// --- predicates ---

// Sign returns -1, 0 or +1 as d is negative, zero or positive.
func (d Dec) Sign() int {
	if d.hi == 0 && d.lo == 0 {
		return 0
	}
	if d.neg {
		return -1
	}
	return 1
}

// IsZero reports whether d is 0.
func (d Dec) IsZero() bool { return d.hi == 0 && d.lo == 0 }

// IsNegative reports whether d is less than 0.
func (d Dec) IsNegative() bool { return d.neg }

// IsPositive reports whether d is greater than 0.
func (d Dec) IsPositive() bool { return !d.neg && !d.IsZero() }

// IsInteger reports whether d has no fractional part.
func (d Dec) IsInteger() bool {
	_, _, _, rem := divmod256by128(from128(d.hi, d.lo), 0, scale)
	return rem == 0
}

// Cmp returns -1, 0 or +1 as d is less than, equal to or greater than e.
func (d Dec) Cmp(e Dec) int {
	ds, es := d.Sign(), e.Sign()
	if ds != es {
		if ds < es {
			return -1
		}
		return 1
	}
	c := cmp128(d.hi, d.lo, e.hi, e.lo)
	if ds < 0 {
		return -c
	}
	return c
}

// Equal reports whether d and e hold the same value.
func (d Dec) Equal(e Dec) bool { return d == e }

// Lt reports whether d < e.
func (d Dec) Lt(e Dec) bool { return d.Cmp(e) < 0 }

// Lte reports whether d <= e.
func (d Dec) Lte(e Dec) bool { return d.Cmp(e) <= 0 }

// Gt reports whether d > e.
func (d Dec) Gt(e Dec) bool { return d.Cmp(e) > 0 }

// Gte reports whether d >= e.
func (d Dec) Gte(e Dec) bool { return d.Cmp(e) >= 0 }

// Min returns the smaller of d and e.
func (d Dec) Min(e Dec) Dec {
	if d.Cmp(e) <= 0 {
		return d
	}
	return e
}

// Max returns the larger of d and e.
func (d Dec) Max(e Dec) Dec {
	if d.Cmp(e) >= 0 {
		return d
	}
	return e
}

// --- arithmetic ---

// Neg returns -d.
func (d Dec) Neg() Dec { return mkDec(!d.neg, d.hi, d.lo) }

// Abs returns |d|.
func (d Dec) Abs() Dec { return mkDec(false, d.hi, d.lo) }

// Add returns d+e. It panics on overflow.
func (d Dec) Add(e Dec) Dec {
	if d.neg == e.neg {
		hi, lo, carry := add128(d.hi, d.lo, e.hi, e.lo)
		if carry != 0 {
			panic(errOverflow)
		}
		return mkDec(d.neg, hi, lo)
	}
	// Opposite signs: the larger magnitude keeps its sign.
	if cmp128(d.hi, d.lo, e.hi, e.lo) >= 0 {
		hi, lo := sub128(d.hi, d.lo, e.hi, e.lo)
		return mkDec(d.neg, hi, lo)
	}
	hi, lo := sub128(e.hi, e.lo, d.hi, d.lo)
	return mkDec(e.neg, hi, lo)
}

// Sub returns d-e. It panics on overflow.
func (d Dec) Sub(e Dec) Dec { return d.Add(e.Neg()) }

// Mul returns d*e rounded half to even.
func (d Dec) Mul(e Dec) Dec { return d.MulRound(e, RoundHalfEven) }

// MulRound returns d*e rounded with mode. The product is formed at full
// 256-bit width, so only the final rescale by 10**18 rounds.
func (d Dec) MulRound(e Dec, mode RoundingMode) Dec {
	n := mul128(d.hi, d.lo, e.hi, e.lo)
	hi, lo := divRound(n, 0, scale, mode)
	return mkDec(d.neg != e.neg, hi, lo)
}

// Div returns d/e rounded half to even. It panics if e is zero.
func (d Dec) Div(e Dec) Dec { return d.DivRound(e, RoundHalfEven) }

// DivRound returns d/e rounded with mode. It panics if e is zero.
func (d Dec) DivRound(e Dec, mode RoundingMode) Dec {
	if e.IsZero() {
		panic(errDivByZero)
	}
	n := mul128(d.hi, d.lo, 0, scale)
	hi, lo := divRound(n, e.hi, e.lo, mode)
	return mkDec(d.neg != e.neg, hi, lo)
}

// MulDiv returns d*e/f with a single rounding step: the product is kept at
// 256-bit width and divided before anything is discarded, so it is exact where
// d.Mul(e).Div(f) would round twice. It panics if f is zero.
func (d Dec) MulDiv(e, f Dec, mode RoundingMode) Dec {
	if f.IsZero() {
		panic(errDivByZero)
	}
	n := mul128(d.hi, d.lo, e.hi, e.lo)
	hi, lo := divRound(n, f.hi, f.lo, mode)
	return mkDec(d.neg != e.neg != f.neg, hi, lo)
}

// Pow returns d**n, rounding half to even after each intermediate
// multiplication. Pow(0) is 1 for every d, including zero.
func (d Dec) Pow(n uint64) Dec {
	res := One()
	base := d
	for n > 0 {
		if n&1 == 1 {
			res = res.Mul(base)
		}
		n >>= 1
		if n > 0 {
			base = base.Mul(base)
		}
	}
	return res
}

// Sqrt returns the square root of d truncated toward zero. It panics if d is
// negative.
func (d Dec) Sqrt() Dec {
	if d.neg {
		panic(errNegSqrt)
	}
	hi, lo := isqrt256(mul128(d.hi, d.lo, 0, scale))
	return mkDec(false, hi, lo)
}

// --- rounding ---

// RoundTo returns d rounded to places fractional digits, keeping the full
// 18-digit representation. places must be in [0, Decimals]. Rounding a value
// within one step of the representable maximum away from zero overflows and
// panics; [Dec.StringFixed] formats such a value instead of rescaling it.
func (d Dec) RoundTo(places int, mode RoundingMode) Dec {
	if places < 0 || places > Decimals {
		panic(errPlaces)
	}
	if places == Decimals {
		return d
	}
	p := pow10tab[Decimals-places]
	hi, lo := divRound(from128(d.hi, d.lo), 0, p, mode)
	n := mul128(hi, lo, 0, p)
	if n[2] != 0 || n[3] != 0 {
		panic(errOverflow)
	}
	return mkDec(d.neg, n[1], n[0])
}

// Truncate returns d with its fractional part dropped, rounding toward zero.
func (d Dec) Truncate() Dec { return d.RoundTo(0, RoundTowardZero) }

// Floor returns the greatest integer not greater than d.
func (d Dec) Floor() Dec {
	if d.neg {
		return d.RoundTo(0, RoundAwayFromZero)
	}
	return d.RoundTo(0, RoundTowardZero)
}

// Ceil returns the least integer not less than d.
func (d Dec) Ceil() Dec {
	if d.neg {
		return d.RoundTo(0, RoundTowardZero)
	}
	return d.RoundTo(0, RoundAwayFromZero)
}

// TruncInt64 returns the integer part of d and reports whether it fits in an
// int64.
func (d Dec) TruncInt64() (int64, bool) {
	qHi, qLo, _, _ := divmod256by128(from128(d.hi, d.lo), 0, scale)
	if qHi != 0 {
		return 0, false
	}
	if d.neg {
		if qLo > 1<<63 {
			return 0, false
		}
		if qLo == 1<<63 {
			return -1 << 63, true
		}
		return -int64(qLo), true
	}
	if qLo > 1<<63-1 {
		return 0, false
	}
	return int64(qLo), true
}

// divRound divides the 256-bit n by the 128-bit (dHi, dLo) and applies mode to
// the remainder. It panics if the rounded quotient needs more than 128 bits.
func divRound(n u256, dHi, dLo uint64, mode RoundingMode) (uint64, uint64) {
	if mode > RoundAwayFromZero {
		panic(errMode)
	}
	qHi, qLo, rHi, rLo := divmod256by128(n, dHi, dLo)
	if rHi == 0 && rLo == 0 {
		return qHi, qLo
	}

	// d = 2*half + odd, so 2*rem > d is rem > half, and 2*rem == d is
	// rem == half with d even. Both comparisons stay inside 128 bits.
	halfHi, halfLo := shr128(dHi, dLo)
	c := cmp128(rHi, rLo, halfHi, halfLo)
	tie := c == 0 && dLo&1 == 0

	up := false
	switch mode {
	case RoundTowardZero:
	case RoundAwayFromZero:
		up = true
	case RoundHalfUp:
		up = c > 0 || tie
	case RoundHalfEven:
		up = c > 0 || (tie && qLo&1 == 1)
	}
	if !up {
		return qHi, qLo
	}

	hi, lo, carry := add128(qHi, qLo, 0, 1)
	if carry != 0 {
		panic(errOverflow)
	}
	return hi, lo
}
