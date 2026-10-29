# fixed

Exact fixed-point decimal arithmetic with 18 fractional digits.

A `Dec` is a sign plus a 128-bit count of 10<sup>-18</sup> units, so it covers
±340282366920938463463.374607431768211455 with every fractional digit exact.
Tenths add up to exactly one, and nothing is rescaled behind your back.

```go
import "gno.land/p/nt/fixed/v0"

price := fixed.MustParse("1.05")
qty   := fixed.FromUint64(250)
gross := price.Mul(qty)                                        // 262.5
fee   := gross.MulDiv(fixed.MustParse("0.3"),
                      fixed.FromUint64(100),
                      fixed.RoundTowardZero)                   // 0.7875
```

## What it gives you

- **Exact decimals.** `0.1 + 0.2` is `0.3`, not `0.30000000000000004`.
- **One rounding step.** `Mul`, `Div` and `MulDiv` form the product at full
  256-bit width and round once, at the end. `MulDiv` is exact where
  `a.Mul(b).Div(c)` rounds twice — with 1-unit operands the two-step form
  returns 0 and `MulDiv` returns 1 unit.
- **Explicit rounding.** `RoundHalfEven` (the default and the zero value),
  `RoundHalfUp`, `RoundTowardZero`, `RoundAwayFromZero`. Every mode acts on the
  magnitude, so it treats -0.5 and 0.5 alike.
- **Comparable values.** Zero is always stored positive, so `==` and map keys
  work; `Equal` says the same thing.
- **Loud failure.** Overflow, division by zero and `Sqrt` of a negative value
  panic instead of wrapping. In a realm that aborts the transaction.

## API

| | |
|---|---|
| Build | `Zero`, `One`, `Smallest`, `FromInt64`, `FromUint64`, `NewFrac`, `FromUnits`, `Parse`, `MustParse` |
| Inspect | `Sign`, `IsZero`, `IsNegative`, `IsPositive`, `IsInteger`, `Cmp`, `Equal`, `Lt`, `Lte`, `Gt`, `Gte`, `Min`, `Max`, `Units` |
| Compute | `Add`, `Sub`, `Neg`, `Abs`, `Mul`, `MulRound`, `Div`, `DivRound`, `MulDiv`, `Pow`, `Sqrt` |
| Shape | `RoundTo`, `Truncate`, `Floor`, `Ceil`, `TruncInt64` |
| Print | `String`, `StringFixed` |

## Choices worth knowing

**Why 128 bits and not 256.** A 128-bit magnitude covers 3.4×10<sup>20</sup> at
18 decimals, which holds any realistic token amount, and it fits two machine
words. Intermediates are 256-bit, so precision is never the thing that is lost
— only range. `Add` and `Mul` panic at the edge rather than silently wrapping.

**Why no external dependency.** The 256-bit intermediates are built on
`math/bits` inside this package, so `fixed` pulls in nothing but the standard
library.

**`Sqrt` truncates.** It returns the largest `r` with `r*r <= d`, the behaviour
AMM reserve math expects. `Pow` rounds half to even after each intermediate
multiplication; it is not a single-rounding operation.

**`RoundTo` can overflow.** It keeps all 18 digits, so rounding a value within
one step of the maximum away from zero leaves the range and panics.
`StringFixed` formats the rounded digits directly and never overflows.

**Division is shift-subtract** when the divisor exceeds 64 bits; rescaling by
10<sup>18</sup> — the common path through `Mul` and all formatting — takes a
word-at-a-time fast path instead.

## Status

v0, unaudited.
