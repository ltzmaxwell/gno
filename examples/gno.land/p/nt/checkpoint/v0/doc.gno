// v0 - Unaudited: This is an initial version that has not yet been formally audited.
// A fully audited version will be published as a subsequent release.
// Use in production at your own risk.
//
// Package checkpoint records how a value changed over time and answers what
// it was at a past height.
//
// Governance needs this. A vote has to weigh balances as they stood when the
// proposal opened, or the same tokens can be moved from account to account
// and voted again; a snapshot taken at the proposal's height is what makes
// the weight unforgeable. [History] is that snapshot, kept incrementally:
// each change appends one entry, and a lookup binary-searches it.
//
// [Votes] builds delegated voting power on top — balances, a delegate per
// account, and a checkpointed power total per delegate — the Gno counterpart
// of ERC20Votes, with one deliberate difference noted on the type.
//
// Heights are passed in rather than read from the chain, so the same code
// checkpoints by block height, timestamp or epoch and stays testable without
// a chain context. A realm normally passes runtime.ChainHeight().
package checkpoint
