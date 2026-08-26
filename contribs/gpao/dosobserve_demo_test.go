package main

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/gnolang/gno/gno.land/pkg/gnoclient"
	"github.com/gnolang/gno/gno.land/pkg/gnoland"
	"github.com/gnolang/gno/gno.land/pkg/integration"
	vm "github.com/gnolang/gno/gno.land/pkg/sdk/vm"
	"github.com/gnolang/gno/gnovm/pkg/gnoenv"
	rpcclient "github.com/gnolang/gno/tm2/pkg/bft/rpc/client"
	"github.com/gnolang/gno/tm2/pkg/log"
	"github.com/gnolang/gno/tm2/pkg/std"
	"github.com/stretchr/testify/require"
)

// observeDepth is the demo knob. The walk is ~35ns/node, and a depth-d doubling
// chain is ~2^(d+1) nodes, so:
//
//	26  ~1e8 nodes   ~35s      long enough to watch the height freeze
//	27  ~2e8 nodes   ~70s
//	28  ~4e8 nodes   ~2.5m
//
// Raise it to make the freeze longer. There is no pass condition: this test only
// prints a timeline, and it is skipped unless run explicitly.
const observeDepth = 26

// TestObserveNodeStopsMakingProgress is not a test — it is an instrument. It fires
// ONE unprivileged MsgRun whose type-check is an unmetered ~35s validType walk, and
// from a second goroutine polls the chain's block height once a second. On
// origin/master (walk unpriced) the height stops advancing for the whole walk while
// the node is occupied by a single transaction: the practical meaning of "halt" —
// no other user's transaction can be included while this one runs.
//
//	go test ./contribs/gpao -run TestObserveNodeStopsMakingProgress -v -timeout 30m -args -observe
//
// Skipped by default because it is slow and has nothing to assert. A halt cannot be
// asserted, only watched.
func TestObserveNodeStopsMakingProgress(t *testing.T) {
	if !observeFlag {
		t.Skip("observation demo; run with -args -observe")
	}

	gnoroot := gnoenv.RootDir()
	cfg := integration.TestingMinimalNodeConfig(gnoroot)
	cfg.SkipGenesisSigVerification = true

	signer, err := gnoclient.SignerFromBip39(
		integration.DefaultAccount_Seed, cfg.Genesis.ChainID, "", 0, 0)
	require.NoError(t, err)
	info, err := signer.Info()
	require.NoError(t, err)
	who := info.GetAddress()

	ggs := cfg.Genesis.AppState.(gnoland.GnoGenesisState)
	ggs.Balances = []gnoland.Balance{
		{Address: who, Amount: std.NewCoins(std.NewCoin("ugnot", 100_000_000_000))},
	}
	cfg.Genesis.AppState = ggs
	cfg.Genesis.ConsensusParams.Block.MaxGas = 3_000_000_000 // production default

	node, remote := integration.TestingInMemoryNode(t, log.NewNoopLogger(), cfg)
	defer node.Stop()
	rpc, err := rpcclient.NewHTTPClient(remote)
	require.NoError(t, err)
	client := gnoclient.Client{Signer: signer, RPCClient: rpc}

	// read fires the cheapest possible query an ordinary user might make and reports
	// how long the node took to answer it. This is the signal: during the walk the
	// node is occupied and cannot serve anyone else.
	read := func() (int64, time.Duration) {
		start := time.Now()
		h, err := client.LatestBlockHeight()
		if err != nil {
			return -1, time.Since(start)
		}
		return h, time.Since(start)
	}

	t0 := time.Now()
	stamp := func() string { return fmt.Sprintf("%5s", time.Since(t0).Round(time.Second)) }

	// Baseline: a few reads before the attack. These return in milliseconds.
	for range 3 {
		h, d := read()
		t.Logf("%s  read -> height=%d in %v  (idle)", stamp(), h, d.Round(time.Millisecond))
		time.Sleep(time.Second)
	}

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		msg := vm.NewMsgRun(who, nil, []*std.MemFile{
			{Name: "code.gno", Body: fanOutSrc("main", observeDepth) + "\nfunc main() {}\n"},
		})
		tx, err := client.SignTx(std.Tx{
			Msgs: []std.Msg{msg},
			Fee:  std.NewFee(3_000_000_000, std.MustParseCoin("400000000ugnot")),
		}, 0, 0)
		require.NoError(t, err)
		start := time.Now()
		_, err = client.BroadcastTxCommit(tx)
		t.Logf("%s  attacker's MsgRun returned after %v (err=%v)",
			stamp(), time.Since(start).Round(time.Second), err)
	}()

	// Keep firing ordinary reads back to back. Each line is what a normal user would
	// experience at that moment. When one read blocks for tens of seconds, or comes
	// back -1, the node is not serving them: the practical halt.
	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	for {
		select {
		case <-done:
			h, d := read()
			t.Logf("%s  read -> height=%d in %v  (walk done, node serving again)",
				stamp(), h, d.Round(time.Millisecond))
			return
		default:
			h, d := read()
			note := ""
			if d > 3*time.Second || h < 0 {
				note = "  <-- ordinary user NOT served"
			}
			t.Logf("%s  read -> height=%d in %v%s", stamp(), h, d.Round(time.Millisecond), note)
			time.Sleep(500 * time.Millisecond)
		}
	}
}
