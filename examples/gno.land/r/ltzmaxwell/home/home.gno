// Package home is ltzmaxwell's home page on gno.land.
package home

import (
	"strings"

	"gno.land/p/nt/ownable/v0"
	"gno.land/p/nt/ufmt/v0"
)

const ownerAddr address = "g1xnv893735y5ef0we0e8w3empa55lnvkfcmn3qs"

const maxNews = 280

var (
	owner = ownable.NewWithAddress(ownerAddr)
	news  []string // oldest first
)

const intro = `# ltzmaxwell

I work on the GnoVM, the engine that runs every realm on gno.land: the type
checker, how realm state is saved and hashed, gas costs, and gnoprove, a tool
that proves promises about Gno code before it is deployed.

## Apps

- [Sigil](/r/ltzmaxwell/sigil) — claim sigils from a published list with a
  short proof; sigils carry voting power and cannot be bought or moved.
- [Poll](/r/ltzmaxwell/poll) — votes weighed by the points each voter held
  when the poll opened.

## Libraries

- [p/nt/merkleproof](/p/nt/merkleproof/v0) — proofs that an entry is in a
  committed list, and a bitmap of what has been claimed.
- [p/nt/checkpoint](/p/nt/checkpoint/v0) — what a balance or voting power
  was at a past block.
- [p/nt/fixed](/p/nt/fixed/v0) — exact 18-decimal arithmetic.
- [p/nt/eip712](/p/nt/eip712/v0) — EIP-191 and EIP-712 message digests.

## Elsewhere

- GitHub: [ltzmaxwell](https://github.com/ltzmaxwell)
`

// AddNews appends one line to the news list; owner only.
func AddNews(cur realm, line string) {
	owner.AssertOwnedBy(cur.Previous().Address())
	line = strings.TrimSpace(line)
	if line == "" || len(line) > maxNews || strings.ContainsAny(line, "\r\n") {
		panic(ufmt.Sprintf("news must be one line of 1..%d bytes", maxNews))
	}
	news = append(news, line)
}

func Render(path string) string {
	var b strings.Builder
	b.WriteString(intro)
	if len(news) > 0 {
		b.WriteString("\n## News\n\n")
		for i := len(news) - 1; i >= 0 && i >= len(news)-10; i-- {
			b.WriteString("- " + news[i] + "\n")
		}
	}
	return b.String()
}
