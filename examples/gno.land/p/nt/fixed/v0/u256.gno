package fixed

import "math/bits"

// u256 is a little-endian 256-bit unsigned integer: w[0] holds the least
// significant 64 bits. It exists only to carry the intermediate products and
// dividends of Dec arithmetic without losing bits.
type u256 [4]uint64

// from128 widens a 128-bit magnitude.
func from128(hi, lo uint64) u256 {
	return u256{lo, hi, 0, 0}
}

func (n u256) isZero() bool {
	return n[0]|n[1]|n[2]|n[3] == 0
}

// bitLen returns the position of the highest set bit, or 0 for zero.
func (n u256) bitLen() int {
	for i := 3; i >= 0; i-- {
		if n[i] != 0 {
			return i*64 + bits.Len64(n[i])
		}
	}
	return 0
}

func (n u256) cmp(m u256) int {
	for i := 3; i >= 0; i-- {
		if n[i] != m[i] {
			if n[i] < m[i] {
				return -1
			}
			return 1
		}
	}
	return 0
}

func (n u256) add(m u256) u256 {
	var r u256
	var c uint64
	r[0], c = bits.Add64(n[0], m[0], 0)
	r[1], c = bits.Add64(n[1], m[1], c)
	r[2], c = bits.Add64(n[2], m[2], c)
	r[3], _ = bits.Add64(n[3], m[3], c)
	return r
}

// sub returns n-m; the caller guarantees n >= m.
func (n u256) sub(m u256) u256 {
	var r u256
	var b uint64
	r[0], b = bits.Sub64(n[0], m[0], 0)
	r[1], b = bits.Sub64(n[1], m[1], b)
	r[2], b = bits.Sub64(n[2], m[2], b)
	r[3], _ = bits.Sub64(n[3], m[3], b)
	return r
}

func (n u256) shl1() u256 {
	return u256{
		n[0] << 1,
		n[1]<<1 | n[0]>>63,
		n[2]<<1 | n[1]>>63,
		n[3]<<1 | n[2]>>63,
	}
}

func (n u256) shr1() u256 {
	return u256{
		n[0]>>1 | n[1]<<63,
		n[1]>>1 | n[2]<<63,
		n[2]>>1 | n[3]<<63,
		n[3] >> 1,
	}
}

func (n u256) shl(s int) u256 {
	if s <= 0 {
		return n
	}
	if s >= 256 {
		return u256{}
	}
	w, b := s/64, uint(s%64)
	var r u256
	for i := 3; i >= w; i-- {
		if b == 0 {
			r[i] = n[i-w]
			continue
		}
		r[i] = n[i-w] << b
		if i-w-1 >= 0 {
			r[i] |= n[i-w-1] >> (64 - b)
		}
	}
	return r
}

// mul128 returns the exact 256-bit product of two 128-bit magnitudes.
func mul128(aHi, aLo, bHi, bLo uint64) u256 {
	var r u256
	var c uint64

	h, l := bits.Mul64(aLo, bLo)
	r[0], r[1] = l, h

	h, l = bits.Mul64(aLo, bHi)
	r[1], c = bits.Add64(r[1], l, 0)
	r[2], c = bits.Add64(r[2], h, c)
	r[3] += c

	h, l = bits.Mul64(aHi, bLo)
	r[1], c = bits.Add64(r[1], l, 0)
	r[2], c = bits.Add64(r[2], h, c)
	r[3] += c

	h, l = bits.Mul64(aHi, bHi)
	r[2], c = bits.Add64(r[2], l, 0)
	r[3], _ = bits.Add64(r[3], h, c)

	return r
}

// divmod256by128 divides n by the 128-bit divisor (dHi, dLo). It panics if the
// divisor is zero or if the quotient needs more than 128 bits. The remainder is
// always smaller than the divisor and so always fits.
func divmod256by128(n u256, dHi, dLo uint64) (qHi, qLo, rHi, rLo uint64) {
	if dHi == 0 {
		if dLo == 0 {
			panic(errDivByZero)
		}
		// A 64-bit divisor divides word by word; this is the path taken by
		// every rescale by 10**18.
		q3, r3 := bits.Div64(0, n[3], dLo)
		q2, r2 := bits.Div64(r3, n[2], dLo)
		q1, r1 := bits.Div64(r2, n[1], dLo)
		q0, r0 := bits.Div64(r1, n[0], dLo)
		if q3 != 0 || q2 != 0 {
			panic(errOverflow)
		}
		return q1, q0, 0, r0
	}

	d := from128(dHi, dLo)
	if n.cmp(d) < 0 {
		return 0, 0, n[1], n[0]
	}

	// Restoring shift-subtract division, starting at the first bit position
	// where the shifted divisor can still fit inside n.
	shift := n.bitLen() - d.bitLen()
	dd := d.shl(shift)
	rem := n
	var q u256
	for i := shift; i >= 0; i-- {
		q = q.shl1()
		if rem.cmp(dd) >= 0 {
			rem = rem.sub(dd)
			q[0] |= 1
		}
		dd = dd.shr1()
	}
	if q[2] != 0 || q[3] != 0 {
		panic(errOverflow)
	}
	return q[1], q[0], rem[1], rem[0]
}

// isqrt256 returns the largest r with r*r <= n. The result always fits in 128
// bits because n is at most 2**256-1.
func isqrt256(n u256) (hi, lo uint64) {
	bl := n.bitLen()
	if bl == 0 {
		return 0, 0
	}
	// Start from the largest power of four not exceeding n.
	s := bl - 1
	if s%2 != 0 {
		s--
	}
	bit := u256{1, 0, 0, 0}.shl(s)

	var res u256
	rem := n
	for !bit.isZero() {
		t := res.add(bit)
		if rem.cmp(t) >= 0 {
			rem = rem.sub(t)
			res = res.shr1().add(bit)
		} else {
			res = res.shr1()
		}
		bit = bit.shr1().shr1()
	}
	return res[1], res[0]
}

// --- 128-bit helpers ---

func cmp128(aHi, aLo, bHi, bLo uint64) int {
	if aHi != bHi {
		if aHi < bHi {
			return -1
		}
		return 1
	}
	if aLo != bLo {
		if aLo < bLo {
			return -1
		}
		return 1
	}
	return 0
}

func add128(aHi, aLo, bHi, bLo uint64) (hi, lo, carry uint64) {
	var c uint64
	lo, c = bits.Add64(aLo, bLo, 0)
	hi, carry = bits.Add64(aHi, bHi, c)
	return hi, lo, carry
}

// sub128 returns a-b; the caller guarantees a >= b.
func sub128(aHi, aLo, bHi, bLo uint64) (hi, lo uint64) {
	var b0 uint64
	lo, b0 = bits.Sub64(aLo, bLo, 0)
	hi, _ = bits.Sub64(aHi, bHi, b0)
	return hi, lo
}

func shr128(hi, lo uint64) (uint64, uint64) {
	return hi >> 1, lo>>1 | hi<<63
}

// mulAdd128 returns a*m+c, reporting false if the result exceeds 128 bits.
func mulAdd128(aHi, aLo, m, c uint64) (hi, lo uint64, ok bool) {
	h1, l1 := bits.Mul64(aLo, m)
	h2, l2 := bits.Mul64(aHi, m)
	if h2 != 0 {
		return 0, 0, false
	}
	hi, carry := bits.Add64(h1, l2, 0)
	if carry != 0 {
		return 0, 0, false
	}
	lo, carry = bits.Add64(l1, c, 0)
	hi, carry = bits.Add64(hi, 0, carry)
	if carry != 0 {
		return 0, 0, false
	}
	return hi, lo, true
}
