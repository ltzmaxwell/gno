package eip712

import (
	"crypto/keccak256"
	"strconv"
)

// HashPersonalMessage returns the EIP-191 version 0x45 digest of message:
// keccak256("\x19Ethereum Signed Message:\n" + len(message) + message).
//
// This is what a wallet's personal_sign produces. The prefix is what keeps a
// signed login challenge from doubling as a signed transaction.
func HashPersonalMessage(message []byte) []byte {
	prefix := "\x19Ethereum Signed Message:\n" + strconv.Itoa(len(message))
	buf := make([]byte, 0, len(prefix)+len(message))
	buf = append(buf, prefix...)
	buf = append(buf, message...)
	sum := keccak256.Sum256(buf)
	return sum[:]
}
