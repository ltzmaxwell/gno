# eip712

The digests an Ethereum wallet signs: EIP-191 personal messages and EIP-712
typed data.

```go
import "gno.land/p/nt/eip712/v0"

d := eip712.Domain{Name: "Ether Mail", Version: "1", ChainID: 1,
                   VerifyingContract: "0xCcCC...ccC"}
sep, _ := d.Separator()

th, _   := eip712.TypeHash(types, "Mail")
hs, _   := eip712.HashStruct(th, from, to, eip712.EncodeString("Hello, Bob!"))
digest, _ := eip712.Digest(sep, hs)        // the 32 bytes the wallet signs
```

## Read this before using it

**This is half of "sign with MetaMask, act on Gno."** The other half is
recovering the signer from the signature, and it is not possible today: Gno's
standard library has no secp256k1, so a 65-byte Ethereum signature cannot be
turned back into an address on chain. Supplying one means a native binding in
`gnovm/stdlibs` with a measured gas cost — a VM change, not an examples
package.

So: use this to produce digests, and to check them against what a wallet or an
off-chain verifier computed. Do not build an authorization path on it.

## The parts

- `HashPersonalMessage(msg)` — EIP-191 version `0x45`, what `personal_sign`
  produces.
- `EncodeType` / `TypeHash` — the canonical type string, with nested struct
  dependencies resolved and sorted by name as the spec requires. Field types
  are validated, so a `uint257` is an error rather than a silently different
  hash.
- Field encoders — `EncodeUint64`, `EncodeInt64` (sign-extended), `EncodeBool`,
  `EncodeAddress` (right-aligned), `EncodeBytesN` (left-aligned),
  `EncodeWord`, `EncodeString`, `EncodeBytes`, `EncodeArray`.
- `HashStruct`, `Domain.Separator`, `Digest`.

Every hash is checked against the Mail example published in EIP-712, computed
independently before being pinned.

## Status

v0, unaudited.
