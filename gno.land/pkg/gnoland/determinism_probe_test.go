package gnoland

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/gnolang/gno/gno.land/pkg/sdk/vm"
	"github.com/gnolang/gno/gnovm/pkg/gnolang"
	"github.com/gnolang/gno/tm2/pkg/amino"
	abci "github.com/gnolang/gno/tm2/pkg/bft/abci/types"
	bft "github.com/gnolang/gno/tm2/pkg/bft/types"
	"github.com/gnolang/gno/tm2/pkg/crypto"
	"github.com/gnolang/gno/tm2/pkg/crypto/ed25519"
	"github.com/gnolang/gno/tm2/pkg/db/memdb"
	"github.com/gnolang/gno/tm2/pkg/sdk"
	"github.com/gnolang/gno/tm2/pkg/std"
)

// probeResult is what a node exposes to consensus for one deploy.
type probeResult struct {
	apphash  string
	gasUsed  int64
	deliverK bool
	errText  string
}

func (r probeResult) String() string {
	return fmt.Sprintf("apphash=%s gas=%d ok=%v err=%q", r.apphash, r.gasUsed, r.deliverK, r.errText)
}

// runProbeApp builds a fresh in-process gnoland app, deploys `pre` packages first
// (to vary cache warmth / history), then deploys `subject` and returns what the
// node would publish. restart, if true, throws the app away after the warm-up
// blocks and rebuilds it from the same DB before the subject tx.
func runProbeApp(t *testing.T, pre []string, subject string, restart bool) probeResult {
	t.Helper()
	// Real signatures, one deterministic key per package. An empty signature only
	// works for a tx delivered in InitChain's genesis context; a tx in a real block
	// is verified, so the warm-up blocks need signing. Keys are derived from a fixed
	// seed so every scenario signs identically.
	keyFor := func(n string) crypto.PrivKey {
		var seed [32]byte
		copy(seed[:], n)
		return ed25519.GenPrivKeyFromSecret(seed[:])
	}
	subjectKey := keyFor("subject")
	db := memdb.NewMemDB()

	build := func() *sdk.BaseApp {
		app, err := NewAppWithOptions(TestAppOptions(db))
		require.NoError(t, err)
		return app.(*sdk.BaseApp)
	}

	deployTx := func(key crypto.PrivKey, path string, accNum uint64) []byte {
		name := path[strings.LastIndexByte(path, '/')+1:]
		tx := std.Tx{
			Msgs: []std.Msg{vm.NewMsgAddPackage(key.PubKey().Address(), path, []*std.MemFile{
				{Name: "gnomod.toml", Body: gnolang.GenGnoModLatest(path)},
				{Name: name + ".gno", Body: "package " + name +
					"\n\ntype T struct{ a, b [0]U }\ntype U struct{ v int }\n"},
			})},
			Fee: std.Fee{GasWanted: 50_000_000, GasFee: std.Coin{Denom: "ugnot", Amount: 1_000_000}},
		}
		sb, err := tx.GetSignBytes("dev", accNum, 0)
		require.NoError(t, err)
		sig, err := key.Sign(sb)
		require.NoError(t, err)
		tx.Signatures = []std.Signature{{PubKey: key.PubKey(), Signature: sig}}
		return amino.MustMarshal(tx)
	}

	bapp := build()
	appState := DefaultGenState()
	// Deterministic account numbers: warm-ups first, subject last, so the subject's
	// accNum is identical in every scenario with the same number of warm-ups.
	appState.Balances = nil
	for _, p := range pre {
		appState.Balances = append(appState.Balances,
			Balance{Address: keyFor(p).PubKey().Address(), Amount: []std.Coin{{Amount: 1e15, Denom: "ugnot"}}})
	}
	appState.Balances = append(appState.Balances,
		Balance{Address: subjectKey.PubKey().Address(), Amount: []std.Coin{{Amount: 1e15, Denom: "ugnot"}}})
	resp := bapp.InitChain(abci.RequestInitChain{
		Time:    time.Unix(0, 0), // fixed: wall clock must not enter the result
		ChainID: "dev",
		ConsensusParams: &abci.ConsensusParams{
			Block: defaultBlockParams(),
		},
		Validators: []abci.ValidatorUpdate{},
		AppState:   appState,
	})
	require.True(t, resp.IsOK(), "InitChain: %v", resp)

	// Warm-up: each pre package in its own block. Commit() clears deliverState, so
	// every block after the first needs its own BeginBlock, as a real node does.
	height := int64(1)
	beginBlock := func() {
		bapp.BeginBlock(abci.RequestBeginBlock{
			Header: &bft.Header{ChainID: "dev", Height: height, Time: time.Unix(height, 0)},
		})
		height++
	}
	for i, p := range pre {
		if i > 0 {
			beginBlock()
		}
		r := bapp.DeliverTx(abci.RequestDeliverTx{Tx: deployTx(keyFor(p), p, uint64(i))})
		require.True(t, r.IsOK(), "warmup deploy %s: %v", p, r)
		bapp.Commit()
	}

	if restart {
		bapp = build() // same DB, fresh in-memory state
	}
	if len(pre) > 0 {
		beginBlock()
	}

	dr := bapp.DeliverTx(abci.RequestDeliverTx{Tx: deployTx(subjectKey, subject, uint64(len(pre)))})
	cres := bapp.Commit()
	return probeResult{
		apphash:  fmt.Sprintf("%X", cres.Data),
		gasUsed:  dr.GasUsed,
		deliverK: dr.IsOK(),
		errText:  fmt.Sprint(dr.Error),
	}
}

// TestProbeReplicaDeterminism — question 1: is the committed apphash reproducible across
// two independently built apps given identical input?
func TestProbeReplicaDeterminism(t *testing.T) {
	a := runProbeApp(t, nil, "gno.land/p/demo/subject", false)
	b := runProbeApp(t, nil, "gno.land/p/demo/subject", false)
	fmt.Printf("REPLICA A: %v\nREPLICA B: %v\nmatch=%v\n", a, b, a == b)
}

// TestProbeRestartInvariance — question 3: two nodes reach the same state by
// different routes, then price the same deploy. Node A deploys the subject cold;
// node B has already deployed two unrelated packages, so its caches are warm.
// The subject's gas must not care.
func TestProbeRestartInvariance(t *testing.T) {
	cold := runProbeApp(t, nil, "gno.land/p/demo/subject", false)
	warm := runProbeApp(t, []string{"gno.land/p/demo/w1", "gno.land/p/demo/w2"},
		"gno.land/p/demo/subject", false)
	restarted := runProbeApp(t, []string{"gno.land/p/demo/w1", "gno.land/p/demo/w2"},
		"gno.land/p/demo/subject", true)
	fmt.Printf("COLD:      %v\nWARM:      %v\nRESTARTED: %v\n", cold, warm, restarted)
	fmt.Printf("gas cold=%d warm=%d restarted=%d  (apphash differs by design: different history)\n",
		cold.gasUsed, warm.gasUsed, restarted.gasUsed)
}
