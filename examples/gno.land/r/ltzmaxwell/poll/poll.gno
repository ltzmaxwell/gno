// Package poll runs polls weighed by sigils. Power is read as of the
// block before the poll opened, so points claimed or delegated afterwards
// do not change who can vote or how much.
package poll

import (
	"chain/runtime"
	"strconv"
	"strings"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/r/ltzmaxwell/sigil"
)

const (
	maxQuestion = 200
	maxOption   = 60
	maxOptions  = 10
	maxBlocks   = 1_000_000
)

type poll struct {
	question string
	options  []string
	tally    []int64
	snapshot int64 // power is counted as of this height
	end      int64 // last height that accepts votes
	creator  address
	voters   *avl.Tree // address -> option index
}

var polls []*poll

// NewPoll opens a poll; options are separated by "|". Only accounts with
// voting power may open one. It accepts votes for the next blocks blocks.
func NewPoll(cur realm, question, options string, blocks int64) int {
	caller := cur.Previous().Address()
	if sigil.Power(caller) <= 0 {
		panic("only accounts with voting power can open a poll")
	}
	question = strings.TrimSpace(question)
	if question == "" || len(question) > maxQuestion || strings.ContainsAny(question, "\r\n") {
		panic(ufmt.Sprintf("question must be one line of 1..%d bytes", maxQuestion))
	}
	opts := strings.Split(options, "|")
	if len(opts) < 2 || len(opts) > maxOptions {
		panic(ufmt.Sprintf("need 2..%d options", maxOptions))
	}
	for i, o := range opts {
		o = strings.TrimSpace(o)
		if o == "" || len(o) > maxOption || strings.ContainsAny(o, "\r\n|") {
			panic(ufmt.Sprintf("option must be 1..%d bytes", maxOption))
		}
		opts[i] = o
	}
	if blocks < 1 || blocks > maxBlocks {
		panic(ufmt.Sprintf("blocks must be 1..%d", maxBlocks))
	}
	now := runtime.ChainHeight()
	polls = append(polls, &poll{
		question: question,
		options:  opts,
		tally:    make([]int64, len(opts)),
		snapshot: now - 1,
		end:      now + blocks,
		creator:  caller,
		voters:   avl.NewTree(),
	})
	return len(polls) - 1
}

// Vote casts the caller's power at the poll's snapshot for one option.
// Each account votes once.
func Vote(cur realm, id int, option int) {
	caller := cur.Previous().Address()
	p := mustPoll(id)
	if runtime.ChainHeight() > p.end {
		panic("poll is closed")
	}
	if option < 0 || option >= len(p.options) {
		panic("no option " + strconv.Itoa(option))
	}
	if p.voters.Has(caller.String()) {
		panic("already voted")
	}
	power := sigil.PastPower(caller, p.snapshot)
	if power <= 0 {
		panic("no voting power at this poll's snapshot")
	}
	p.tally[option] += power
	p.voters.Set(caller.String(), option)
}

func Render(path string) string {
	if path != "" {
		id, err := strconv.Atoi(path)
		if err != nil {
			return "404"
		}
		return renderPoll(id)
	}
	var b strings.Builder
	b.WriteString("# Poll\n\nVotes weighed by sigils from [Sigil](/r/ltzmaxwell/sigil) held ")
	b.WriteString("the block before a poll opened.\n\n")
	if len(polls) == 0 {
		b.WriteString("No polls yet.\n")
		return b.String()
	}
	now := runtime.ChainHeight()
	for i := len(polls) - 1; i >= 0; i-- {
		p := polls[i]
		state := "open"
		if now > p.end {
			state = "closed"
		}
		b.WriteString(ufmt.Sprintf("- [%s](/r/ltzmaxwell/poll:%d) — %s, %d voters\n",
			p.question, i, state, p.voters.Size()))
	}
	return b.String()
}

func renderPoll(id int) string {
	if id < 0 || id >= len(polls) {
		return "404"
	}
	p := polls[id]
	var cast int64
	for _, v := range p.tally {
		cast += v
	}
	supply := sigil.PastTotalSupply(p.snapshot)
	var b strings.Builder
	b.WriteString(ufmt.Sprintf("# %s\n\n", p.question))
	b.WriteString("| option | power | share |\n|---|---|---|\n")
	for i, o := range p.options {
		b.WriteString(ufmt.Sprintf("| %d. %s | %d | %s |\n", i, o, p.tally[i], pct(p.tally[i], cast)))
	}
	b.WriteString(ufmt.Sprintf("\nTurnout: %d of %d (%s). Snapshot block %d, open through block %d. Opened by %s.\n",
		cast, supply, pct(cast, supply), p.snapshot, p.end, p.creator.String()))
	return b.String()
}

// pct renders a/b as a percentage with one decimal.
func pct(a, b int64) string {
	if b <= 0 {
		return "-"
	}
	x := a * 1000 / b
	return ufmt.Sprintf("%d.%d%%", x/10, x%10)
}

func mustPoll(id int) *poll {
	if id < 0 || id >= len(polls) {
		panic("no poll " + strconv.Itoa(id))
	}
	return polls[id]
}
