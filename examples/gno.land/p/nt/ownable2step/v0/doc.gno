// v0 - Unaudited: This is an initial version that has not yet been formally audited.
// A fully audited version will be published as a subsequent release.
// Use in production at your own risk.
//
// Package ownable2step provides single-owner authorization in which a transfer
// takes two transactions: the owner nominates a successor, and the successor
// accepts. A typo in the nominated address is therefore recoverable — the
// owner simply nominates again — where the one-step
// gno.land/p/nt/ownable/v0 loses the realm permanently.
//
// It replicates Ownable rather than wrapping it, because it cannot wrap it:
// AcceptOwnership runs with the pending owner as the principal, and every
// ownership-mutating method on Ownable asserts that the principal is the
// current owner. Promoting the pending owner through the inner Ownable would
// need an unchecked setter that Ownable deliberately does not expose.
package ownable2step
