# ownable2step

Single-owner authorization where a transfer takes two transactions: the owner
nominates a successor, and the successor accepts.

```go
o := ownable2step.NewWithAddress(owner)
o.TransferOwnership(0, cur, candidate) // nominates; owner still in charge
o.AcceptOwnership(0, cur)              // called by candidate; now owner
```

A typo in the nominated address is recoverable — nominate again — where the
one-step `gno.land/p/nt/ownable/v0` loses the realm permanently.

It replicates `Ownable` rather than wrapping it, and cannot do otherwise:
`AcceptOwnership` runs with the *pending* owner as the principal, while every
ownership-mutating method on `Ownable` asserts the principal is the *current*
owner. Promoting through an inner `Ownable` would need an unchecked setter it
deliberately does not expose.

## Status

v0, unaudited. Promoted from `p/oxtekgrinder/ownable2step`.
