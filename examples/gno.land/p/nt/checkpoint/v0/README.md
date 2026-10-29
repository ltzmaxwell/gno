# checkpoint

What a value was at a past height, and delegated voting power built on it.

A vote has to weigh balances as they stood when the proposal opened. Otherwise
the same tokens move from account to account and vote again.

```go
import "gno.land/p/nt/checkpoint/v0"

v := checkpoint.NewVotes()
v.Mint(height, alice, 1000)
v.Delegate(height, alice, bob)              // power moves, balance does not

power := v.PastPower(alice, proposalHeight) // fixed when the proposal opened
quorum := v.PastTotalSupply(proposalHeight)
```

## The parts

- `History` — an append-only list of `(height, value)` with a binary-search
  lookup. Several changes in one block collapse into one entry, so no
  intermediate value is ever visible to a later lookup, and a redundant push
  records nothing.
- `Votes` — balances, a delegate per account, a checkpointed power total per
  delegate, and a checkpointed supply. `Mint`, `Burn`, `Transfer`, `Delegate`.

## Choices worth knowing

**Self-delegation is the default.** Holding tokens is enough to have voting
power. ERC20Votes requires an explicit `delegate` call and gives an account
that never made one no power at all, however large its balance; that has
silently disenfranchised real holders. Delegate back to the account itself to
undo a delegation.

**Heights are passed in, not read from the chain.** The same code then
checkpoints by block height, timestamp or epoch, and the package stays
testable without a chain context. A realm passes `runtime.ChainHeight()`.

**Only power and supply are checkpointed**, not balances — that is all a vote
needs, and it keeps a transfer to O(log n) plus two appends.

**Updates are all-or-nothing.** A transfer touches two power histories; both
are checked before either moves, so a rejected update cannot leave power
disagreeing with balances.

**`Votes` is a ledger, not a policy.** It has no notion of who may call what;
a realm wraps it with its own authorization.

## Status

v0, unaudited.
