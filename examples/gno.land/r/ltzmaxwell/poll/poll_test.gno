package poll

import (
	"encoding/hex"
	"strings"
	"testing"

	"gno.land/p/nt/merkleproof/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/ltzmaxwell/sigil"
)

const ownerAddr address = "g1xnv893735y5ef0we0e8w3empa55lnvkfcmn3qs"

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

func claim(cur realm, t *testing.T, tr *merkleproof.Tree, id, i int, who address, amount int64) {
	p, err := tr.Proof(i)
	if err != nil {
		t.Fatal(err)
	}
	s := make([]string, len(p))
	for j, h := range p {
		s[j] = hex.EncodeToString(h)
	}
	testing.SetRealm(testing.NewUserRealm(who))
	sigil.Claim(cross(cur), id, uint64(i), amount, strings.Join(s, ","))
}

func TestPoll(cur realm, t *testing.T) {
	tr, _ := merkleproof.NewTree([][]byte{
		merkleproof.AirdropLeaf(0, alice, 60),
		merkleproof.AirdropLeaf(1, bob, 40),
		merkleproof.AirdropLeaf(2, carol, 900),
	})
	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	id := sigil.NewRound(cross(cur), "r1", hex.EncodeToString(tr.Root()), 1000)
	claim(cur, t, tr, id, 0, alice, 60)
	claim(cur, t, tr, id, 1, bob, 40)

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "only accounts with voting power can open a poll", func() {
		NewPoll(cross(cur), "q?", "a|b", 10)
	})

	testing.SkipHeights(1)
	testing.SetRealm(testing.NewUserRealm(alice))
	pid := NewPoll(cross(cur), "Ship v1?", "yes|no", 10)

	// carol claims after the snapshot: her 900 points do not count here.
	claim(cur, t, tr, id, 2, carol, 900)
	uassert.AbortsWithMessage(t, cur, "no voting power at this poll's snapshot", func() {
		Vote(cross(cur), pid, 1)
	})

	testing.SetRealm(testing.NewUserRealm(alice))
	Vote(cross(cur), pid, 0)
	uassert.AbortsWithMessage(t, cur, "already voted", func() { Vote(cross(cur), pid, 0) })
	testing.SetRealm(testing.NewUserRealm(bob))
	Vote(cross(cur), pid, 1)

	out := Render("0")
	uassert.True(t, strings.Contains(out, "| 0. yes | 60 | 60.0% |"), out)
	uassert.True(t, strings.Contains(out, "Turnout: 100 of 100 (100.0%)"), out)

	testing.SkipHeights(11)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "poll is closed", func() { Vote(cross(cur), pid, 1) })
	uassert.True(t, strings.Contains(Render(""), "Ship v1?](/r/ltzmaxwell/poll:0) — closed, 2 voters"))
}
