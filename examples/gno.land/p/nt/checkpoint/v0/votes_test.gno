package checkpoint

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

func TestMintTransferBurn(t *testing.T) {
	v := NewVotes()

	if err := v.Mint(10, alice, 1000); err != nil {
		t.Fatalf("Mint: %v", err)
	}
	assertState(t, v, "after mint", alice, 1000, 1000)
	if got := v.TotalSupply(); got != 1000 {
		t.Errorf("supply = %d, want 1000", got)
	}

	if err := v.Transfer(20, alice, bob, 400); err != nil {
		t.Fatalf("Transfer: %v", err)
	}
	assertState(t, v, "after transfer", alice, 600, 600)
	assertState(t, v, "after transfer", bob, 400, 400)
	if got := v.TotalSupply(); got != 1000 {
		t.Errorf("supply changed on transfer: %d", got)
	}

	if err := v.Burn(30, bob, 400); err != nil {
		t.Fatalf("Burn: %v", err)
	}
	assertState(t, v, "after burn", bob, 0, 0)
	if got := v.TotalSupply(); got != 600 {
		t.Errorf("supply = %d, want 600", got)
	}
}

// TestSelfDelegationIsTheDefault is the documented difference from
// ERC20Votes: holding tokens is enough to have power.
func TestSelfDelegationIsTheDefault(t *testing.T) {
	v := NewVotes()
	if got := v.DelegateOf(alice); got != alice {
		t.Errorf("DelegateOf = %s, want the account itself", got)
	}
	if err := v.Mint(10, alice, 500); err != nil {
		t.Fatal(err)
	}
	if got := v.Power(alice); got != 500 {
		t.Errorf("power without an explicit delegate = %d, want 500", got)
	}
}

func TestDelegateMovesPowerNotBalance(t *testing.T) {
	v := NewVotes()
	mustMint(t, v, 10, alice, 1000)

	if err := v.Delegate(20, alice, bob); err != nil {
		t.Fatalf("Delegate: %v", err)
	}
	if got := v.Balance(alice); got != 1000 {
		t.Errorf("delegating moved the balance: %d", got)
	}
	if got := v.Power(alice); got != 0 {
		t.Errorf("alice kept power after delegating: %d", got)
	}
	if got := v.Power(bob); got != 1000 {
		t.Errorf("bob power = %d, want 1000", got)
	}
	if got := v.DelegateOf(alice); got != bob {
		t.Errorf("DelegateOf = %s, want bob", got)
	}

	// A later credit follows the delegation.
	mustMint(t, v, 30, alice, 500)
	if got := v.Power(bob); got != 1500 {
		t.Errorf("bob power after alice was credited = %d, want 1500", got)
	}

	// Delegating back restores the default.
	if err := v.Delegate(40, alice, alice); err != nil {
		t.Fatalf("Delegate back: %v", err)
	}
	if got := v.Power(alice); got != 1500 {
		t.Errorf("alice power after taking it back = %d", got)
	}
	if got := v.Power(bob); got != 0 {
		t.Errorf("bob kept power = %d", got)
	}
	if got := v.DelegateOf(alice); got != alice {
		t.Errorf("DelegateOf = %s, want alice", got)
	}
}

// TestPastPowerIsNotRewritten is the property the whole package exists for: a
// snapshot taken when a proposal opened cannot be changed by moving tokens
// afterwards, so the same tokens cannot vote twice.
func TestPastPowerIsNotRewritten(t *testing.T) {
	v := NewVotes()
	mustMint(t, v, 10, alice, 1000)

	const proposalHeight = int64(50)
	if got := v.PastPower(alice, proposalHeight); got != 1000 {
		t.Fatalf("alice power at the proposal = %d, want 1000", got)
	}
	if got := v.PastPower(bob, proposalHeight); got != 0 {
		t.Fatalf("bob power at the proposal = %d, want 0", got)
	}

	// Alice votes, then hands everything to bob.
	if err := v.Transfer(60, alice, bob, 1000); err != nil {
		t.Fatalf("Transfer: %v", err)
	}

	if got := v.PastPower(alice, proposalHeight); got != 1000 {
		t.Errorf("alice's snapshot changed: %d", got)
	}
	if got := v.PastPower(bob, proposalHeight); got != 0 {
		t.Errorf("bob could vote the same tokens: %d", got)
	}
	if got := v.Power(bob); got != 1000 {
		t.Errorf("bob current power = %d, want 1000", got)
	}

	// Delegation after the fact cannot rewrite it either.
	if err := v.Delegate(70, bob, carol); err != nil {
		t.Fatalf("Delegate: %v", err)
	}
	if got := v.PastPower(carol, proposalHeight); got != 0 {
		t.Errorf("carol gained retroactive power: %d", got)
	}
}

func TestPastTotalSupply(t *testing.T) {
	v := NewVotes()
	mustMint(t, v, 10, alice, 100)
	mustMint(t, v, 20, bob, 400)
	if err := v.Burn(30, alice, 50); err != nil {
		t.Fatal(err)
	}

	tests := []struct{ at, want int64 }{
		{5, 0}, {10, 100}, {19, 100}, {20, 500}, {29, 500}, {30, 450}, {99, 450},
	}
	for _, tt := range tests {
		if got := v.PastTotalSupply(tt.at); got != tt.want {
			t.Errorf("PastTotalSupply(%d) = %d, want %d", tt.at, got, tt.want)
		}
	}
}

func TestVotesRejects(t *testing.T) {
	v := NewVotes()
	mustMint(t, v, 10, alice, 100)

	tests := []struct {
		name string
		do   func() error
		want error
	}{
		{"negative mint", func() error { return v.Mint(20, bob, -1) }, ErrNegativeAmount},
		{"negative burn", func() error { return v.Burn(20, alice, -1) }, ErrNegativeAmount},
		{"negative transfer", func() error { return v.Transfer(20, alice, bob, -1) }, ErrNegativeAmount},
		{"burn past balance", func() error { return v.Burn(20, alice, 101) }, ErrInsufficientBalance},
		{"transfer past balance", func() error { return v.Transfer(20, alice, bob, 101) }, ErrInsufficientBalance},
		{"transfer from empty", func() error { return v.Transfer(20, carol, bob, 1) }, ErrInsufficientBalance},
		{"mint below the last height", func() error { return v.Mint(5, alice, 1) }, ErrHeightWentBackwards},
		{"transfer below the last height", func() error { return v.Transfer(5, alice, bob, 1) }, ErrHeightWentBackwards},
		{"mint overflows the supply", func() error { return v.Mint(20, bob, 1<<62) }, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.do()
			if tt.want != nil && err != tt.want {
				t.Errorf("err = %v, want %v", err, tt.want)
			}
		})
	}

	// Everything above either failed or was a legal mint; alice is untouched.
	if got := v.Balance(alice); got != 100 {
		t.Errorf("alice balance = %d, want 100", got)
	}
	if got := v.Power(alice); got != 100 {
		t.Errorf("alice power = %d, want 100", got)
	}
}

func TestOverflowIsRejectedWhole(t *testing.T) {
	v := NewVotes()
	const huge = int64(4_000_000_000_000_000_000)
	mustMint(t, v, 10, alice, huge)
	mustMint(t, v, 11, bob, huge)

	// A third mint of the same size would take the supply past int64.
	if err := v.Mint(12, carol, huge); err != ErrOverflow {
		t.Fatalf("overflowing mint = %v, want ErrOverflow", err)
	}
	if got := v.TotalSupply(); got != 2*huge {
		t.Errorf("supply changed: %d", got)
	}
	if got := v.Balance(carol); got != 0 {
		t.Errorf("carol was credited: %d", got)
	}
	if got := v.Power(carol); got != 0 {
		t.Errorf("carol gained power: %d", got)
	}

	// Concentrating every balance on one delegate, by contrast, can never
	// overflow: power totals sum to the supply, which already fits.
	if err := v.Delegate(13, alice, bob); err != nil {
		t.Fatalf("Delegate: %v", err)
	}
	if got := v.Power(bob); got != 2*huge {
		t.Errorf("bob power = %d, want %d", got, 2*huge)
	}
	if got := v.Power(alice); got != 0 {
		t.Errorf("alice power = %d, want 0", got)
	}
}

func TestTransferToSelfIsANoOp(t *testing.T) {
	v := NewVotes()
	mustMint(t, v, 10, alice, 100)
	if err := v.Transfer(20, alice, alice, 50); err != nil {
		t.Fatalf("Transfer: %v", err)
	}
	if got := v.Balance(alice); got != 100 {
		t.Errorf("balance = %d, want 100", got)
	}
	if got := v.PowerHistory(alice).Len(); got != 1 {
		t.Errorf("a self transfer added %d entries, want none beyond the mint", got-1)
	}
}

func TestDelegateToCurrentDelegateIsANoOp(t *testing.T) {
	v := NewVotes()
	mustMint(t, v, 10, alice, 100)
	if err := v.Delegate(20, alice, alice); err != nil {
		t.Fatalf("Delegate: %v", err)
	}
	if got := v.PowerHistory(alice).Len(); got != 1 {
		t.Errorf("redundant delegation added entries: Len = %d", got)
	}
}

func assertState(t *testing.T, v *Votes, when string, who address, balance, power int64) {
	t.Helper()
	if got := v.Balance(who); got != balance {
		t.Errorf("%s: balance = %d, want %d", when, got, balance)
	}
	if got := v.Power(who); got != power {
		t.Errorf("%s: power = %d, want %d", when, got, power)
	}
}

func mustMint(t *testing.T, v *Votes, height int64, who address, amount int64) {
	t.Helper()
	if err := v.Mint(height, who, amount); err != nil {
		t.Fatalf("Mint(%d,%s,%d): %v", height, who, amount, err)
	}
}
