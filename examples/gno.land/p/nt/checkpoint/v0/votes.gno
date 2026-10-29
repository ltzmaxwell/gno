package checkpoint

import (
	"errors"

	"gno.land/p/nt/avl/v0"
)

var (
	// ErrNegativeAmount is returned for an amount below zero.
	ErrNegativeAmount = errors.New("checkpoint: negative amount")
	// ErrInsufficientBalance is returned when an account cannot cover a
	// transfer or a burn.
	ErrInsufficientBalance = errors.New("checkpoint: insufficient balance")
	// ErrOverflow is returned when a balance, a power total or the supply
	// would leave the int64 range.
	ErrOverflow = errors.New("checkpoint: overflow")
)

// Votes is delegated voting power with a checkpointed history, the Gno
// counterpart of ERC20Votes.
//
// Balances are held here and mirrored into a power total per delegate, and
// only the power totals and the supply are checkpointed: that is all a vote
// needs, and it keeps a transfer to O(log n) plus two appends.
//
// One deliberate difference from ERC20Votes: an account delegates to itself
// by default, so holding tokens is enough to vote. In ERC20Votes an account
// that never calls delegate has no voting power however large its balance,
// which has silently disenfranchised real holders. Call Delegate to point the
// power elsewhere, and Delegate back to the account itself to take it back.
//
// Votes keeps no notion of who may call what. It is a ledger; a realm wraps
// it with its own authorization.
type Votes struct {
	balances  *avl.Tree // address -> int64
	delegates *avl.Tree // address -> address, absent means self
	power     *avl.Tree // delegate address -> *History
	total     *History
}

// NewVotes returns an empty ledger.
func NewVotes() *Votes {
	return &Votes{
		balances:  avl.NewTree(),
		delegates: avl.NewTree(),
		power:     avl.NewTree(),
		total:     NewHistory(),
	}
}

// Balance returns the balance of account.
func (v *Votes) Balance(account address) int64 {
	if raw := v.balances.Get(account.String()); raw != nil {
		return raw.(int64)
	}
	return 0
}

// DelegateOf returns the account whose power this account's balance counts
// towards, which is the account itself unless it delegated away.
func (v *Votes) DelegateOf(account address) address {
	if raw := v.delegates.Get(account.String()); raw != nil {
		return raw.(address)
	}
	return account
}

// Power returns the current voting power of account: the balances of every
// account delegating to it, including its own when it has not delegated away.
func (v *Votes) Power(account address) int64 {
	return v.history(account).Latest()
}

// PastPower returns the voting power of account as of height. This is the
// number a vote should weigh, read at the height the proposal opened.
func (v *Votes) PastPower(account address, height int64) int64 {
	return v.history(account).At(height)
}

// TotalSupply returns the current supply.
func (v *Votes) TotalSupply() int64 { return v.total.Latest() }

// PastTotalSupply returns the supply as of height, the denominator a quorum
// is measured against.
func (v *Votes) PastTotalSupply(height int64) int64 { return v.total.At(height) }

// PowerHistory returns the checkpoint history behind account's power. The
// returned History is the live one; treat it as read-only.
func (v *Votes) PowerHistory(account address) *History { return v.history(account) }

// Mint credits account and raises the supply.
func (v *Votes) Mint(height int64, account address, amount int64) error {
	if amount < 0 {
		return ErrNegativeAmount
	}
	newTotal, ok := addChecked(v.total.Latest(), amount)
	if !ok {
		return ErrOverflow
	}
	newBalance, ok := addChecked(v.Balance(account), amount)
	if !ok {
		return ErrOverflow
	}
	if err := v.total.canPush(height); err != nil {
		return err
	}
	if err := v.movePower(height, address(""), v.DelegateOf(account), amount); err != nil {
		return err
	}
	v.total.Push(height, newTotal)
	v.setBalance(account, newBalance)
	return nil
}

// Burn debits account and lowers the supply.
func (v *Votes) Burn(height int64, account address, amount int64) error {
	if amount < 0 {
		return ErrNegativeAmount
	}
	balance := v.Balance(account)
	if balance < amount {
		return ErrInsufficientBalance
	}
	if err := v.total.canPush(height); err != nil {
		return err
	}
	if err := v.movePower(height, v.DelegateOf(account), address(""), amount); err != nil {
		return err
	}
	v.total.Push(height, v.total.Latest()-amount)
	v.setBalance(account, balance-amount)
	return nil
}

// Transfer moves amount between accounts, and with it the power between their
// delegates. The supply does not change.
func (v *Votes) Transfer(height int64, from, to address, amount int64) error {
	if amount < 0 {
		return ErrNegativeAmount
	}
	fromBalance := v.Balance(from)
	if fromBalance < amount {
		return ErrInsufficientBalance
	}
	if from == to || amount == 0 {
		return nil
	}
	toBalance, ok := addChecked(v.Balance(to), amount)
	if !ok {
		return ErrOverflow
	}
	if err := v.movePower(height, v.DelegateOf(from), v.DelegateOf(to), amount); err != nil {
		return err
	}
	v.setBalance(from, fromBalance-amount)
	v.setBalance(to, toBalance)
	return nil
}

// Delegate points account's balance at the voting power of to. Delegating to
// the account itself restores the default.
func (v *Votes) Delegate(height int64, account, to address) error {
	current := v.DelegateOf(account)
	if current == to {
		return nil
	}
	if err := v.movePower(height, current, to, v.Balance(account)); err != nil {
		return err
	}
	if to == account {
		v.delegates.Remove(account.String())
	} else {
		v.delegates.Set(account.String(), to)
	}
	return nil
}

// movePower subtracts amount from one delegate's power and adds it to
// another's, checkpointing both. The empty address stands for outside the
// ledger, as it does for a mint or a burn.
func (v *Votes) movePower(height int64, from, to address, amount int64) error {
	if amount == 0 || from == to {
		return nil
	}

	// Check both sides before moving either, so a rejected move leaves the
	// two power totals consistent with the balances.
	var fromHist, toHist *History
	if from != "" {
		fromHist = v.history(from)
		if err := fromHist.canPush(height); err != nil {
			return err
		}
		if _, ok := addChecked(fromHist.Latest(), -amount); !ok {
			return ErrOverflow
		}
	}
	if to != "" {
		toHist = v.history(to)
		if err := toHist.canPush(height); err != nil {
			return err
		}
		if _, ok := addChecked(toHist.Latest(), amount); !ok {
			return ErrOverflow
		}
	}

	if fromHist != nil {
		fromHist.Add(height, -amount)
	}
	if toHist != nil {
		toHist.Add(height, amount)
	}
	return nil
}

// history returns account's power history, creating it on first use.
func (v *Votes) history(account address) *History {
	key := account.String()
	if raw := v.power.Get(key); raw != nil {
		return raw.(*History)
	}
	h := NewHistory()
	v.power.Set(key, h)
	return h
}

func (v *Votes) setBalance(account address, amount int64) {
	if amount == 0 {
		v.balances.Remove(account.String())
		return
	}
	v.balances.Set(account.String(), amount)
}

// addChecked returns a+b and whether it stayed inside int64.
func addChecked(a, b int64) (int64, bool) {
	s := a + b
	if (b > 0 && s < a) || (b < 0 && s > a) {
		return 0, false
	}
	return s, true
}
