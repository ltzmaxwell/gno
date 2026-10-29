package eip712

import (
	"crypto/keccak256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"strings"
)

// WordSize is the width of one encoded EIP-712 field.
const WordSize = 32

var (
	// ErrBadAddress is returned for a string that is not a 20-byte 0x-hex
	// Ethereum address.
	ErrBadAddress = errors.New("eip712: not a 20-byte hex address")
	// ErrBadWord is returned when a value does not fit one 32-byte word.
	ErrBadWord = errors.New("eip712: value is not 32 bytes")
)

// EncodeUint64 encodes v as a right-aligned 32-byte word.
func EncodeUint64(v uint64) []byte {
	var w [WordSize]byte
	binary.BigEndian.PutUint64(w[WordSize-8:], v)
	return w[:]
}

// EncodeInt64 encodes v as a 32-byte two's complement word, sign-extended.
func EncodeInt64(v int64) []byte {
	var w [WordSize]byte
	if v < 0 {
		for i := range w {
			w[i] = 0xff
		}
	}
	binary.BigEndian.PutUint64(w[WordSize-8:], uint64(v))
	return w[:]
}

// EncodeBool encodes a bool as a 32-byte word holding 0 or 1.
func EncodeBool(b bool) []byte {
	var w [WordSize]byte
	if b {
		w[WordSize-1] = 1
	}
	return w[:]
}

// EncodeWord copies an already 32-byte value, which is how uint256, int256
// and bytes32 arrive when they come from outside.
func EncodeWord(b []byte) ([]byte, error) {
	if len(b) != WordSize {
		return nil, ErrBadWord
	}
	w := make([]byte, WordSize)
	copy(w, b)
	return w, nil
}

// EncodeBytesN left-aligns a bytesN value, which is how fixed byte arrays are
// padded, unlike numbers.
func EncodeBytesN(b []byte) ([]byte, error) {
	if len(b) == 0 || len(b) > WordSize {
		return nil, ErrBadWord
	}
	w := make([]byte, WordSize)
	copy(w, b)
	return w, nil
}

// EncodeAddress encodes a 20-byte Ethereum address given as "0x" and 40 hex
// digits, right-aligned in a 32-byte word. The case of the hex digits is not
// checked against EIP-55.
func EncodeAddress(addr string) ([]byte, error) {
	s := addr
	if strings.HasPrefix(s, "0x") || strings.HasPrefix(s, "0X") {
		s = s[2:]
	}
	if len(s) != 40 {
		return nil, ErrBadAddress
	}
	raw, err := hex.DecodeString(strings.ToLower(s))
	if err != nil {
		return nil, ErrBadAddress
	}
	w := make([]byte, WordSize)
	copy(w[WordSize-20:], raw)
	return w, nil
}

// EncodeString encodes a dynamic string as the hash of its UTF-8 bytes.
func EncodeString(s string) []byte {
	sum := keccak256.Sum256([]byte(s))
	return sum[:]
}

// EncodeBytes encodes dynamic bytes as their hash.
func EncodeBytes(b []byte) []byte {
	sum := keccak256.Sum256(b)
	return sum[:]
}

// EncodeArray encodes an array field as the hash of its already-encoded
// members concatenated.
func EncodeArray(members ...[]byte) ([]byte, error) {
	buf := make([]byte, 0, len(members)*WordSize)
	for _, m := range members {
		if len(m) != WordSize {
			return nil, ErrBadWord
		}
		buf = append(buf, m...)
	}
	sum := keccak256.Sum256(buf)
	return sum[:], nil
}

// HashStruct returns keccak256(typeHash ‖ fields), the hashStruct of the
// spec. fields must be given in declaration order, each already encoded to
// one 32-byte word; a nested struct contributes its own HashStruct.
func HashStruct(typeHash []byte, fields ...[]byte) ([]byte, error) {
	if len(typeHash) != WordSize {
		return nil, ErrBadWord
	}
	buf := make([]byte, 0, WordSize*(1+len(fields)))
	buf = append(buf, typeHash...)
	for _, f := range fields {
		if len(f) != WordSize {
			return nil, ErrBadWord
		}
		buf = append(buf, f...)
	}
	sum := keccak256.Sum256(buf)
	return sum[:], nil
}

// Digest returns the 32 bytes a wallet signs for typed data:
// keccak256(0x19 0x01 ‖ domainSeparator ‖ structHash).
func Digest(domainSeparator, structHash []byte) ([]byte, error) {
	if len(domainSeparator) != WordSize || len(structHash) != WordSize {
		return nil, ErrBadWord
	}
	buf := make([]byte, 0, 2+2*WordSize)
	buf = append(buf, 0x19, 0x01)
	buf = append(buf, domainSeparator...)
	buf = append(buf, structHash...)
	sum := keccak256.Sum256(buf)
	return sum[:], nil
}
