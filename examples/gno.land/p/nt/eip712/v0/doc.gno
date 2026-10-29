// v0 - Unaudited: This is an initial version that has not yet been formally audited.
// A fully audited version will be published as a subsequent release.
// Use in production at your own risk.
//
// Package eip712 builds the digests an Ethereum wallet signs: the EIP-191
// personal-message hash and the EIP-712 typed-data hash.
//
// It is the encoding half of "sign with MetaMask, act on Gno". The other half
// is recovering the signer from the signature, which this package cannot do:
// Gno's standard library has no secp256k1, so there is no way to turn a
// 65-byte Ethereum signature back into an address on chain. Adding one means
// a native binding in gnovm/stdlibs with a measured gas cost, not an examples
// package. Until that exists, use this to produce digests and compare them
// against what a wallet or an off-chain verifier computed; do not build an
// authorization path on it.
//
// What is here is the part that is easy to get subtly wrong: [EncodeType]
// resolves nested struct dependencies and orders them the way the spec
// requires, and the field encoders pad each value into the 32-byte word
// [HashStruct] expects.
package eip712
