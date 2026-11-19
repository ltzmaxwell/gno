package sigil

import (
	"encoding/hex"
	"strings"
	"testing"

	"gno.land/p/nt/merkleproof/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

func proofHex(t *testing.T, tr *merkleproof.Tree, i int) string {
	p, err := tr.Proof(i)
	if err != nil {
		t.Fatal(err)
	}
	s := make([]string, len(p))
	for j, h := range p {
		s[j] = hex.EncodeToString(h)
	}
	return strings.Join(s, ",")
}

func TestSigil(cur realm, t *testing.T) {
	tr, err := merkleproof.NewTree([][]byte{
		merkleproof.AirdropLeaf(0, alice, 100),
		merkleproof.AirdropLeaf(1, bob, 50),
		merkleproof.AirdropLeaf(2, carol, 7),
	})
	if err != nil {
		t.Fatal(err)
	}
	root := hex.EncodeToString(tr.Root())

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "ownable: caller is not owner", func() {
		NewRound(cross(cur), "round 1", root, 157)
	})

	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := NewRound(cross(cur), "round 1", root, 157)
	uassert.Equal(t, 0, id)

	testing.SetRealm(testing.NewUserRealm(alice))
	Claim(cross(cur), id, 0, 100, proofHex(t, tr, 0))
	uassert.Equal(t, int64(100), Balance(alice))
	uassert.True(t, Claimed(id, 0))
	uassert.AbortsWithMessage(t, cur, "merkleproof: already claimed", func() {
		Claim(cross(cur), id, 0, 100, proofHex(t, tr, 0))
	})
	// alice cannot take bob's entry: the leaf is built from the caller.
	uassert.AbortsWithMessage(t, cur, "merkleproof: proof does not match the root", func() {
		Claim(cross(cur), id, 1, 50, proofHex(t, tr, 1))
	})

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, cur, "merkleproof: proof does not match the root", func() {
		Claim(cross(cur), id, 1, 51, proofHex(t, tr, 1))
	})
	Claim(cross(cur), id, 1, 50, proofHex(t, tr, 1))
	Delegate(cross(cur), alice)
	uassert.Equal(t, int64(150), Power(alice))
	uassert.Equal(t, int64(0), Power(bob))
	uassert.Equal(t, int64(150), TotalSupply())

	out := Render("")
	uassert.True(t, strings.Contains(out, "| 0 | round 1 | 2 | 150 / 157 |"), out)
	uassert.True(t, strings.Contains(Render("u/"+alice.String()), "voting power: 150"))
}

func TestRoundOverTotal(cur realm, t *testing.T) {
	// The announced total caps payouts even if the list says more.
	tr, _ := merkleproof.NewTree([][]byte{merkleproof.AirdropLeaf(0, carol, 10)})
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := NewRound(cross(cur), "capped", hex.EncodeToString(tr.Root()), 5)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "amount is outside what this round has left", func() {
		Claim(cross(cur), id, 0, 10, "")
	})
}
