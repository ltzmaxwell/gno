package fixed

import (
	"errors"
	"math/bits"
	"strconv"
)

// chunk is the largest power of ten that fits in a uint64, used to print a
// 128-bit magnitude 19 digits at a time.
const chunk = 10_000_000_000_000_000_000

// Parse converts a plain decimal string such as "12.345", "-0.5" or "+7" into
// a Dec. At most Decimals fractional digits are accepted; exponent notation,
// spaces and digit separators are not.
func Parse(s string) (Dec, error) {
	if s == "" {
		return Dec{}, errors.New("fixed: empty string")
	}

	neg := false
	i := 0
	if s[0] == '+' || s[0] == '-' {
		neg = s[0] == '-'
		i = 1
	}

	var hi, lo uint64
	digits, frac := 0, -1 // frac counts fractional digits once '.' is seen
	for ; i < len(s); i++ {
		c := s[i]
		if c == '.' {
			if frac >= 0 {
				return Dec{}, errors.New("fixed: more than one decimal point: " + s)
			}
			frac = 0
			continue
		}
		if c < '0' || c > '9' {
			return Dec{}, errors.New("fixed: invalid character: " + s)
		}
		if frac >= 0 {
			if frac == Decimals {
				return Dec{}, errors.New("fixed: more than " + strconv.Itoa(Decimals) + " decimal places: " + s)
			}
			frac++
		}
		var ok bool
		hi, lo, ok = mulAdd128(hi, lo, 10, uint64(c-'0'))
		if !ok {
			return Dec{}, errors.New("fixed: value out of range: " + s)
		}
		digits++
	}
	if digits == 0 {
		return Dec{}, errors.New("fixed: no digits: " + s)
	}

	if frac < 0 {
		frac = 0
	}
	hi, lo, ok := mulAdd128(hi, lo, pow10tab[Decimals-frac], 0)
	if !ok {
		return Dec{}, errors.New("fixed: value out of range: " + s)
	}
	return mkDec(neg, hi, lo), nil
}

// MustParse is Parse, panicking on a malformed or out-of-range string. Use it
// for constants written into source.
func MustParse(s string) Dec {
	d, err := Parse(s)
	if err != nil {
		panic(err)
	}
	return d
}

// String returns d in plain decimal notation with trailing fractional zeros
// removed: "0", "1.5", "-0.000000000000000001".
func (d Dec) String() string {
	intHi, intLo, _, rem := divmod256by128(from128(d.hi, d.lo), 0, scale)
	out := u128Decimal(intHi, intLo)
	if rem != 0 {
		f := padDigits(rem, Decimals)
		for len(f) > 0 && f[len(f)-1] == '0' {
			f = f[:len(f)-1]
		}
		out += "." + f
	}
	if d.neg {
		out = "-" + out
	}
	return out
}

// StringFixed returns d with exactly places fractional digits, rounding half
// to even. places must be in [0, Decimals]. It formats the rounded digits
// directly, so unlike [Dec.RoundTo] it never overflows.
func (d Dec) StringFixed(places int) string {
	if places < 0 || places > Decimals {
		panic(errPlaces)
	}
	// Rescale to units of 10**-places; this quotient is never wider than d.
	qHi, qLo := divRound(from128(d.hi, d.lo), 0, pow10tab[Decimals-places], RoundHalfEven)

	intHi, intLo, rem := qHi, qLo, uint64(0)
	if places > 0 {
		intHi, intLo, _, rem = divmod256by128(from128(qHi, qLo), 0, pow10tab[places])
	}

	out := u128Decimal(intHi, intLo)
	if places > 0 {
		out += "." + padDigits(rem, places)
	}
	// Only a value that survived rounding carries a sign; -0.001 at two
	// places is "0.00", not "-0.00".
	if d.neg && !(intHi == 0 && intLo == 0 && rem == 0) {
		out = "-" + out
	}
	return out
}

// u128Decimal renders a 128-bit magnitude in base ten.
func u128Decimal(hi, lo uint64) string {
	if hi == 0 {
		return strconv.FormatUint(lo, 10)
	}
	var parts []string
	for hi != 0 || lo != 0 {
		qh, r := bits.Div64(0, hi, chunk)
		ql, r := bits.Div64(r, lo, chunk)
		hi, lo = qh, ql
		if hi == 0 && lo == 0 {
			parts = append(parts, strconv.FormatUint(r, 10))
		} else {
			parts = append(parts, padDigits(r, 19))
		}
	}
	out := ""
	for i := len(parts) - 1; i >= 0; i-- {
		out += parts[i]
	}
	return out
}

// padDigits renders v in base ten, left-padded with zeros to width.
func padDigits(v uint64, width int) string {
	s := strconv.FormatUint(v, 10)
	for len(s) < width {
		s = "0" + s
	}
	return s
}
