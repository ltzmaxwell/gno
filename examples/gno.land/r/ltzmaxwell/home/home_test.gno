package home

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestNews(cur realm, t *testing.T) {
	uassert.False(t, strings.Contains(Render(""), "## News"))

	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("eve")))
	uassert.AbortsWithMessage(t, cur, "ownable: caller is not owner", func() {
		AddNews(cross(cur), "hi")
	})

	testing.SetRealm(testing.NewUserRealm(ownerAddr))
	AddNews(cross(cur), "first")
	AddNews(cross(cur), "second")
	uassert.AbortsWithMessage(t, cur, "news must be one line of 1..280 bytes", func() {
		AddNews(cross(cur), "a\nb")
	})
	out := Render("")
	uassert.True(t, strings.Index(out, "- second") < strings.Index(out, "- first"))
}
