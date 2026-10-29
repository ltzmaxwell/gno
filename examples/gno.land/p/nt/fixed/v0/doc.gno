// v0 - Unaudited: This is an initial version that has not yet been formally audited.
// A fully audited version will be published as a subsequent release.
// Use in production at your own risk.
//
// Package fixed provides exact fixed-point decimal arithmetic with 18
// fractional digits, the precision most token and price calculations are
// expressed in.
//
// A [Dec] is a signed 128-bit magnitude scaled by 10**18, so values range over
// roughly ±3.4e20 with every one of the 18 fractional digits exact. Unlike
// float64, repeated addition of 0.1 lands on exactly 1.0; unlike raw integer
// arithmetic, products and quotients are rescaled and rounded explicitly
// instead of silently truncating.
//
// Multiplication and division use a full 256-bit intermediate, so no
// representable operation loses precision before rounding, and [Dec.MulDiv]
// rounds once rather than twice. Rounding defaults to half-to-even;
// [RoundingMode] selects another policy per call.
//
// Overflow, division by zero and the square root of a negative number panic
// rather than returning a wrapped value: inside a realm that aborts the
// transaction, which is the safe outcome for a financial calculation.
package fixed
