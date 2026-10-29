// v0 - Unaudited: This is an initial version that has not yet been formally audited.
// A fully audited version will be published as a subsequent release.
// Use in production at your own risk.
//
// Package merkleproof verifies sorted-pair Merkle proofs and tracks which
// indices of a committed list have already been used.
//
// It exists for the airdrop shape: commit one 32-byte root on chain, keep the
// list of recipients off chain, and let each recipient pay for their own
// inclusion proof. A million-entry distribution costs one storage slot plus a
// claim bit per recipient who turns up.
//
// Pairs are hashed sorted, so a proof carries only sibling hashes and no
// direction bits. See [Root] for the exact tree construction an off-chain
// generator has to match, and [LeafHash] for why leaves are hashed twice.
package merkleproof
