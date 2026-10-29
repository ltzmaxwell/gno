# merkleproof

Sorted-pair Merkle proofs, and a bitmap of which committed entries have been
used.

Built for the airdrop shape: commit one 32-byte root, keep the recipient list
off chain, and let each recipient pay for their own inclusion proof. A
million-entry distribution is one storage slot plus a bit per claimer.

```go
import "gno.land/p/nt/merkleproof/v0"

d, _ := merkleproof.NewDistributor(root)           // root committed at deploy
err := d.Claim(index, account, amount, proof)      // verifies, then marks
// err is ErrBadProof or ErrAlreadyClaimed, and marks nothing in either case
```

## The parts

- `Verify(root, leaf, proof)` / `Process(leaf, proof)` — fold a leaf through
  sibling hashes. Pairs are hashed sorted, so a proof carries no direction
  bits.
- `LeafHash(data)` — `keccak256(keccak256(data))`. The second hash is what
  keeps a 64-byte "leaf" from being an internal node in disguise.
- `NewTree(leaves)` / `Root(leaves)` / `Tree.Proof(i)` — build a tree when the
  list is small enough to live on chain, or in tests.
- `Bitmap` — claim bits packed 64 to a word. `Set` reports whether it was the
  call that set the bit, which is the check a claim wants.
- `Distributor` — a root plus a bitmap. `Claim` builds the leaf itself from
  `(index, account, amount)`, so a proof for one entry can never be replayed
  against another entry's bit.

## What an off-chain generator must match

- Leaves are `keccak256(keccak256(entry bytes))`.
- A parent is `keccak256` of its two children concatenated **in ascending byte
  order**.
- When a level holds an odd number of nodes, the last one is **carried up
  unchanged**, not duplicated. A single leaf is its own root.
- `AirdropLeaf` entry bytes are: index as 8 big-endian bytes, the address
  length as 2 big-endian bytes, the address, then amount as 8 big-endian bytes
  two's complement.

## Caveat worth reading

`Verify` trusts whatever 32-byte leaf it is handed, so an internal node of the
tree does verify against the root — that is inherent to the construction, and
pinned by a test. `LeafHash` is the defence, and `Distributor` never lets a
caller supply a leaf. A realm with its own entry shape must hash leaves the
same way.

## Status

v0, unaudited.
