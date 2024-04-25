package rpctest

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	abci "github.com/gnolang/gno/tm2/pkg/bft/abci/types"
	cfg "github.com/gnolang/gno/tm2/pkg/bft/config"
	nm "github.com/gnolang/gno/tm2/pkg/bft/node"
	"github.com/gnolang/gno/tm2/pkg/bft/privval"
	"github.com/gnolang/gno/tm2/pkg/bft/proxy"
	ctypes "github.com/gnolang/gno/tm2/pkg/bft/rpc/core/types"
	rpcclient "github.com/gnolang/gno/tm2/pkg/bft/rpc/lib/client"
	"github.com/gnolang/gno/tm2/pkg/log"
	"github.com/gnolang/gno/tm2/pkg/p2p"
)

// Options helps with specifying some parameters for our RPC testing for greater
// control.
type Options struct {
	suppressStdout bool
	recreateConfig bool
	genesisPath    string
}

var (
	// This entire testing insanity is removed in:
	// https://github.com/gnolang/gno/pull/1498
	globalConfig  *cfg.Config
	globalGenesis string

	defaultOptions = Options{
		recreateConfig: false,
		genesisPath:    "genesis.json",
	}
)

func waitForRPC() {
	cfg, _ := GetConfig()
	laddr := cfg.RPC.ListenAddress
	client := rpcclient.NewJSONRPCClient(laddr)
	result := new(ctypes.ResultStatus)
	for {
		_, err := client.Call("status", map[string]interface{}{}, result)
		if err == nil {
			return
		} else {
			fmt.Println("error", err)
			time.Sleep(time.Millisecond)
		}
	}
}

// f**ing long, but unique for each test
func makePathname() string {
	// get path
	p, err := os.Getwd()
	if err != nil {
		panic(err)
	}
	// fmt.Println(p)
	sep := string(filepath.Separator)
	return strings.Replace(p, sep, "_", -1)
}

func createConfig() (*cfg.Config, string) {
	pathname := makePathname()
	c, genesisFile := cfg.ResetTestRoot(pathname)

	// and we use random ports to run in parallel
	c.P2P.ListenAddress = "tcp://127.0.0.1:0"
	c.RPC.ListenAddress = "tcp://127.0.0.1:0"
	c.RPC.CORSAllowedOrigins = []string{"https://tendermint.com/"}
	// c.TxIndex.IndexTags = "app.creator,tx.height" // see kvstore application
	return c, genesisFile
}

// GetConfig returns a config for the test cases as a singleton
func GetConfig(forceCreate ...bool) (*cfg.Config, string) {
	if globalConfig == nil || globalGenesis == "" || (len(forceCreate) > 0 && forceCreate[0]) {
		globalConfig, globalGenesis = createConfig()
	}
	return globalConfig, globalGenesis
}

// StartTendermint starts a test tendermint server in a go routine and returns when it is initialized
func StartTendermint(app abci.Application, opts ...func(*Options)) *nm.Node {
	nodeOpts := defaultOptions
	for _, opt := range opts {
		opt(&nodeOpts)
	}
	node := NewTendermint(app, &nodeOpts)
	err := node.Start()
	if err != nil {
		panic(err)
	}

	// wait for rpc
	waitForRPC()

	return node
}

// StopTendermint stops a test tendermint server, waits until it's stopped and
// cleans up test/config files.
func StopTendermint(node *nm.Node) {
	node.Stop()
	node.Wait()
	os.RemoveAll(node.Config().RootDir)
}

// NewTendermint creates a new tendermint server and sleeps forever
func NewTendermint(app abci.Application, opts *Options) *nm.Node {
	// Create & start node
	config, genesisFile := GetConfig(opts.recreateConfig)

	pvKeyFile := config.PrivValidatorKeyFile()
	pvKeyStateFile := config.PrivValidatorStateFile()
	pv := privval.LoadOrGenFilePV(pvKeyFile, pvKeyStateFile)
	papp := proxy.NewLocalClientCreator(app)
	nodeKey, err := p2p.LoadOrGenNodeKey(config.NodeKeyFile())
	if err != nil {
		panic(err)
	}
	node, err := nm.NewNode(config, pv, nodeKey, papp,
		nm.DefaultGenesisDocProviderFunc(genesisFile),
		nm.DefaultDBProvider,
		log.NewNoopLogger())
	if err != nil {
		panic(err)
	}
	return node
}

// SuppressStdout is an option that tries to make sure the RPC test Tendermint
// node doesn't log anything to stdout.
func SuppressStdout(o *Options) {
	o.suppressStdout = true
}

// RecreateConfig instructs the RPC test to recreate the configuration each
// time, instead of treating it as a global singleton.
func RecreateConfig(o *Options) {
	o.recreateConfig = true
}
