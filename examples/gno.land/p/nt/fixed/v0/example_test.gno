package fixed_test

import (
	"fmt"

	"gno.land/p/nt/fixed/v0"
)

// A price times a quantity, then a percentage fee, with the rounding policy
// chosen rather than inherited.
func Example() {
	price := fixed.MustParse("1.05")
	qty := fixed.FromUint64(250)

	gross := price.Mul(qty)
	fee := gross.MulDiv(fixed.MustParse("0.3"), fixed.FromUint64(100), fixed.RoundTowardZero)

	fmt.Println("gross:", gross)
	fmt.Println("fee:  ", fee.StringFixed(6))
	fmt.Println("net:  ", gross.Sub(fee).StringFixed(6))
	// Output:
	// gross: 262.5
	// fee:   0.787500
	// net:   261.712500
}

// Tenths add up exactly, which is the difference from float64.
func ExampleDec_Add() {
	sum := fixed.Zero()
	for i := 0; i < 10; i++ {
		sum = sum.Add(fixed.MustParse("0.1"))
	}
	fmt.Println(sum, sum.Equal(fixed.One()))
	// Output: 1 true
}

// MulDiv keeps the product at 256 bits, so it rounds once where a separate
// multiply and divide would round twice.
func ExampleDec_MulDiv() {
	u := fixed.Smallest() // 10**-18

	fmt.Println("two steps:", u.Mul(u).Div(u))
	fmt.Println("one step: ", u.MulDiv(u, u, fixed.RoundHalfEven))
	// Output:
	// two steps: 0
	// one step:  0.000000000000000001
}

// Rounding is explicit; the default is half to even.
func ExampleRoundingMode() {
	d := fixed.MustParse("2.5")
	for _, m := range []fixed.RoundingMode{
		fixed.RoundHalfEven,
		fixed.RoundHalfUp,
		fixed.RoundTowardZero,
		fixed.RoundAwayFromZero,
	} {
		fmt.Print(d.RoundTo(0, m), " ")
	}
	fmt.Println()
	// Output: 2 3 2 3
}

// Sqrt truncates toward zero, as an AMM reserve calculation wants.
func ExampleDec_Sqrt() {
	k := fixed.FromUint64(1_000_000).Mul(fixed.FromUint64(4))
	fmt.Println(k.Sqrt())
	// Output: 2000
}
