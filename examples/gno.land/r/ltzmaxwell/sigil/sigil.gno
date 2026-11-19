// Package sigil hands out sigils, non-transferable points, from published
// lists. The owner commits a list by its Merkle root; each listed account
// claims its own entry with a proof. Sigils cannot be transferred, only
// delegated, so voting power built on them cannot be bought.
package sigil

import (
	"chain/runtime"
	"encoding/hex"
	"strconv"
	"strings"

	"gno.land/p/nt/checkpoint/v0"
	"gno.land/p/nt/merkleproof/v0"
	"gno.land/p/nt/ownable/v0"
	"gno.land/p/nt/ufmt/v0"
)

const ownerAddr address = "g1xnv893735y5ef0we0e8w3empa55lnvkfcmn3qs"

const maxName = 64

type round struct {
	name    string
	total   int64 // announced sum of the list; payouts never exceed it
	paid    int64
	created int64
	dist    *merkleproof.Distributor
}

var (
	owner  = ownable.NewWithAddress(ownerAddr)
	votes  = checkpoint.NewVotes()
	rounds []*round
)

// NewRound commits a list by its root (64 hex chars) and returns its id.
// total is the sum of all amounts in the list. Owner only.
func NewRound(cur realm, name, rootHex string, total int64) int {
	owner.AssertOwnedBy(cur.Previous().Address())
	if name == "" || len(name) > maxName || strings.ContainsAny(name, "\r\n") {
		panic(ufmt.Sprintf("name must be one line of 1..%d bytes", maxName))
	}
	if total <= 0 {
		panic("total must be positive")
	}
	root, err := hex.DecodeString(rootHex)
	checkErr(err)
	dist, err := merkleproof.NewDistributor(root)
	checkErr(err)
	rounds = append(rounds, &round{name: name, total: total, created: runtime.ChainHeight(), dist: dist})
	return len(rounds) - 1
}

// Claim pays the caller its entry in round id. proof is the sibling hashes,
// hex, comma-separated; empty for a one-entry list.
func Claim(cur realm, id int, index uint64, amount int64, proof string) {
	caller := cur.Previous().Address()
	d := mustRound(id)
	if d.dist.Claimed(index) {
		panic(merkleproof.ErrAlreadyClaimed)
	}
	if amount <= 0 || amount > d.total-d.paid {
		panic("amount is outside what this round has left")
	}
	checkErr(d.dist.Claim(index, caller, amount, parseProof(proof)))
	checkErr(votes.Mint(runtime.ChainHeight(), caller, amount))
	d.paid += amount
}

// Delegate gives the caller's voting power to to; delegate to yourself to undo.
func Delegate(cur realm, to address) {
	checkErr(votes.Delegate(runtime.ChainHeight(), cur.Previous().Address(), to))
}

func Balance(addr address) int64                 { return votes.Balance(addr) }
func Power(addr address) int64                   { return votes.Power(addr) }
func DelegateOf(addr address) address            { return votes.DelegateOf(addr) }
func PastPower(addr address, height int64) int64 { return votes.PastPower(addr, height) }
func TotalSupply() int64                         { return votes.TotalSupply() }
func PastTotalSupply(height int64) int64         { return votes.PastTotalSupply(height) }

// Claimed reports whether entry index of round id has been claimed.
func Claimed(id int, index uint64) bool { return mustRound(id).dist.Claimed(index) }

func Render(path string) string {
	if strings.HasPrefix(path, "u/") {
		a := address(path[2:])
		return ufmt.Sprintf("# %s\n\n- sigils: %d\n- voting power: %d\n- delegates to: %s\n",
			a.String(), votes.Balance(a), votes.Power(a), votes.DelegateOf(a).String())
	}
	var b strings.Builder
	b.WriteString("# Sigil\n\nClaim sigils from a published list. Sigils carry voting power in ")
	b.WriteString("[Poll](/r/ltzmaxwell/poll); they cannot be transferred, only delegated.\n\n")
	b.WriteString(ufmt.Sprintf("Sigils in circulation: %d\n\n", votes.TotalSupply()))
	if len(rounds) == 0 {
		b.WriteString("No rounds yet.\n")
		return b.String()
	}
	b.WriteString("| id | name | claims | paid / total | opened at block |\n|---|---|---|---|---|\n")
	for i, d := range rounds {
		b.WriteString(ufmt.Sprintf("| %d | %s | %d | %d / %d | %d |\n",
			i, d.name, int(d.dist.ClaimCount()), d.paid, d.total, d.created))
	}
	b.WriteString("\nYour standing: `/r/ltzmaxwell/sigil:u/<address>`\n")
	return b.String()
}

func mustRound(id int) *round {
	if id < 0 || id >= len(rounds) {
		panic("no round " + strconv.Itoa(id))
	}
	return rounds[id]
}

func parseProof(s string) [][]byte {
	if s == "" {
		return nil
	}
	parts := strings.Split(s, ",")
	out := make([][]byte, len(parts))
	for i, p := range parts {
		h, err := hex.DecodeString(strings.TrimSpace(p))
		if err != nil || len(h) != merkleproof.HashSize {
			panic("proof entry " + strconv.Itoa(i) + " is not 32 bytes of hex")
		}
		out[i] = h
	}
	return out
}

func checkErr(err error) {
	if err != nil {
		panic(err)
	}
}
