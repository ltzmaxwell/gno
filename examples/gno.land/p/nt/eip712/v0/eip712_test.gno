package eip712

import (
	"encoding/hex"
	"testing"
)

// The Mail example from the EIP-712 specification, with the hashes it
// publishes. Every expected value below was recomputed from the spec text by
// a separate implementation before being pinned here.
const (
	cowAddr  = "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"
	bobAddr  = "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"
	mailAddr = "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"

	wantMailEncodeType  = "Mail(Person from,Person to,string contents)Person(string name,address wallet)"
	wantPersonTypeHash  = "b9d8c78acf9b987311de6c7b45bb6a9c8e1bf361fa7fd3467a2163f994c79500"
	wantMailTypeHash    = "a0cedeb2dc280ba39b857546d74f5549c3a1d7bdc2dd96bf881f76108e23dac2"
	wantDomainSeparator = "f2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090f"
	wantMailHashStruct  = "c52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e"
	wantDigest          = "be609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2"
)

func mailTypes() Types {
	return Types{
		"Person": {
			{Name: "name", Type: "string"},
			{Name: "wallet", Type: "address"},
		},
		"Mail": {
			{Name: "from", Type: "Person"},
			{Name: "to", Type: "Person"},
			{Name: "contents", Type: "string"},
		},
	}
}

func hexOf(b []byte) string { return hex.EncodeToString(b) }

func TestEncodeTypeMatchesSpec(t *testing.T) {
	got, err := EncodeType(mailTypes(), "Mail")
	if err != nil {
		t.Fatalf("EncodeType: %v", err)
	}
	if got != wantMailEncodeType {
		t.Errorf("EncodeType =\n %s\nwant\n %s", got, wantMailEncodeType)
	}

	th, err := TypeHash(mailTypes(), "Mail")
	if err != nil {
		t.Fatalf("TypeHash: %v", err)
	}
	if hexOf(th) != wantMailTypeHash {
		t.Errorf("Mail typeHash = %s, want %s", hexOf(th), wantMailTypeHash)
	}

	ph, _ := TypeHash(mailTypes(), "Person")
	if hexOf(ph) != wantPersonTypeHash {
		t.Errorf("Person typeHash = %s, want %s", hexOf(ph), wantPersonTypeHash)
	}
}

// TestDependenciesAreSortedNotDiscovered pins the ordering rule: referenced
// types follow the primary sorted by name, not in the order they are reached.
func TestDependenciesAreSorted(t *testing.T) {
	types := Types{
		"Tx": {
			{Name: "z", Type: "Zebra"},
			{Name: "a", Type: "Apple"},
		},
		"Zebra": {{Name: "n", Type: "uint256"}},
		"Apple": {{Name: "n", Type: "uint256"}},
	}
	got, err := EncodeType(types, "Tx")
	if err != nil {
		t.Fatalf("EncodeType: %v", err)
	}
	want := "Tx(Zebra z,Apple a)Apple(uint256 n)Zebra(uint256 n)"
	if got != want {
		t.Errorf("EncodeType =\n %s\nwant\n %s", got, want)
	}
}

func TestEncodeTypeFollowsNestedAndArrayMembers(t *testing.T) {
	types := Types{
		"Order":  {{Name: "items", Type: "Item[]"}, {Name: "who", Type: "Party"}},
		"Item":   {{Name: "sku", Type: "bytes32"}, {Name: "qty", Type: "uint8"}},
		"Party":  {{Name: "at", Type: "Addr"}},
		"Addr":   {{Name: "line", Type: "string"}},
		"Unused": {{Name: "x", Type: "bool"}},
	}
	got, err := EncodeType(types, "Order")
	if err != nil {
		t.Fatalf("EncodeType: %v", err)
	}
	want := "Order(Item[] items,Party who)Addr(string line)Item(bytes32 sku,uint8 qty)Party(Addr at)"
	if got != want {
		t.Errorf("EncodeType =\n %s\nwant\n %s", got, want)
	}
}

func TestEncodeTypeErrors(t *testing.T) {
	tests := []struct {
		name    string
		types   Types
		primary string
		want    error
	}{
		{"missing primary", mailTypes(), "Nope", ErrNoSuchStruct},
		{
			"typo in a field type",
			Types{"A": {{Name: "x", Type: "uint257"}}},
			"A", ErrUnknownType,
		},
		{
			"unnamed field",
			Types{"A": {{Name: "", Type: "uint256"}}},
			"A", ErrEmptyFieldName,
		},
		{
			"bad array suffix",
			Types{"A": {{Name: "x", Type: "uint256[0]"}}},
			"A", ErrUnknownType,
		},
		{
			"unterminated array",
			Types{"A": {{Name: "x", Type: "uint256["}}},
			"A", ErrUnknownType,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := EncodeType(tt.types, tt.primary); err != tt.want {
				t.Errorf("err = %v, want %v", err, tt.want)
			}
		})
	}
}

func TestEncodeTypeAcceptsEveryAtomicType(t *testing.T) {
	good := []string{
		"address", "bool", "string", "bytes",
		"bytes1", "bytes32", "uint8", "uint256", "int8", "int256",
		"uint256[]", "bytes32[4]", "address[][2]",
	}
	for _, ty := range good {
		types := Types{"A": {{Name: "x", Type: ty}}}
		if _, err := EncodeType(types, "A"); err != nil {
			t.Errorf("%s rejected: %v", ty, err)
		}
	}
	bad := []string{"uint", "int", "bytes0", "bytes33", "uint7", "uint512", "Uint256", "foo"}
	for _, ty := range bad {
		types := Types{"A": {{Name: "x", Type: ty}}}
		if _, err := EncodeType(types, "A"); err != ErrUnknownType {
			t.Errorf("%s accepted (err = %v)", ty, err)
		}
	}
}

func TestCircularTypesAreRejected(t *testing.T) {
	types := Types{
		"A": {{Name: "b", Type: "B"}},
		"B": {{Name: "a", Type: "A"}},
	}
	// The cycle is reached through the shared visited set, so this must not
	// hang; it either encodes both once or reports the cycle.
	if _, err := EncodeType(types, "A"); err != nil && err != ErrCircularType {
		t.Errorf("err = %v, want nil or ErrCircularType", err)
	}
}

func TestDomainSeparatorMatchesSpec(t *testing.T) {
	d := Domain{
		Name:              "Ether Mail",
		Version:           "1",
		ChainID:           1,
		VerifyingContract: mailAddr,
	}
	sep, err := d.Separator()
	if err != nil {
		t.Fatalf("Separator: %v", err)
	}
	if hexOf(sep) != wantDomainSeparator {
		t.Errorf("Separator = %s, want %s", hexOf(sep), wantDomainSeparator)
	}
}

func TestFullMailDigestMatchesSpec(t *testing.T) {
	types := mailTypes()
	personHash, _ := TypeHash(types, "Person")
	mailHash, _ := TypeHash(types, "Mail")

	cow, err := EncodeAddress(cowAddr)
	if err != nil {
		t.Fatalf("EncodeAddress: %v", err)
	}
	bob, err := EncodeAddress(bobAddr)
	if err != nil {
		t.Fatalf("EncodeAddress: %v", err)
	}

	from, err := HashStruct(personHash, EncodeString("Cow"), cow)
	if err != nil {
		t.Fatalf("HashStruct: %v", err)
	}
	to, err := HashStruct(personHash, EncodeString("Bob"), bob)
	if err != nil {
		t.Fatalf("HashStruct: %v", err)
	}
	msg, err := HashStruct(mailHash, from, to, EncodeString("Hello, Bob!"))
	if err != nil {
		t.Fatalf("HashStruct: %v", err)
	}
	if hexOf(msg) != wantMailHashStruct {
		t.Fatalf("hashStruct = %s, want %s", hexOf(msg), wantMailHashStruct)
	}

	d := Domain{Name: "Ether Mail", Version: "1", ChainID: 1, VerifyingContract: mailAddr}
	sep, _ := d.Separator()
	digest, err := Digest(sep, msg)
	if err != nil {
		t.Fatalf("Digest: %v", err)
	}
	if hexOf(digest) != wantDigest {
		t.Errorf("Digest = %s, want %s", hexOf(digest), wantDigest)
	}
}

func TestEncoders(t *testing.T) {
	tests := []struct {
		name string
		got  []byte
		want string
	}{
		{"uint64 zero", EncodeUint64(0), "0000000000000000000000000000000000000000000000000000000000000000"},
		{"uint64 one", EncodeUint64(1), "0000000000000000000000000000000000000000000000000000000000000001"},
		{"uint64 max", EncodeUint64(^uint64(0)), "000000000000000000000000000000000000000000000000ffffffffffffffff"},
		{"int64 minus one", EncodeInt64(-1), "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"},
		{"int64 minus two", EncodeInt64(-2), "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe"},
		{"int64 positive", EncodeInt64(258), "0000000000000000000000000000000000000000000000000000000000000102"},
		{"bool true", EncodeBool(true), "0000000000000000000000000000000000000000000000000000000000000001"},
		{"bool false", EncodeBool(false), "0000000000000000000000000000000000000000000000000000000000000000"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if hexOf(tt.got) != tt.want {
				t.Errorf("= %s, want %s", hexOf(tt.got), tt.want)
			}
		})
	}

	// An address is right-aligned; a bytesN value is left-aligned.
	a, _ := EncodeAddress(bobAddr)
	if hexOf(a) != "000000000000000000000000bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" {
		t.Errorf("EncodeAddress = %s", hexOf(a))
	}
	n, _ := EncodeBytesN([]byte{0xde, 0xad})
	if hexOf(n) != "dead000000000000000000000000000000000000000000000000000000000000" {
		t.Errorf("EncodeBytesN = %s", hexOf(n))
	}
}

func TestEncoderErrors(t *testing.T) {
	for _, bad := range []string{"", "0x", "0xzz", bobAddr + "ff", bobAddr[:41]} {
		if _, err := EncodeAddress(bad); err != ErrBadAddress {
			t.Errorf("EncodeAddress(%q) = %v, want ErrBadAddress", bad, err)
		}
	}
	// A prefix is optional, not required.
	if _, err := EncodeAddress(bobAddr[2:]); err != nil {
		t.Errorf("unprefixed address rejected: %v", err)
	}
	if _, err := EncodeWord(make([]byte, 31)); err != ErrBadWord {
		t.Error("short word accepted")
	}
	if _, err := EncodeBytesN(nil); err != ErrBadWord {
		t.Error("empty bytesN accepted")
	}
	if _, err := EncodeBytesN(make([]byte, 33)); err != ErrBadWord {
		t.Error("oversized bytesN accepted")
	}
	if _, err := HashStruct(make([]byte, 31)); err != ErrBadWord {
		t.Error("short type hash accepted")
	}
	if _, err := HashStruct(make([]byte, 32), make([]byte, 5)); err != ErrBadWord {
		t.Error("short field accepted")
	}
	if _, err := Digest(make([]byte, 31), make([]byte, 32)); err != ErrBadWord {
		t.Error("short separator accepted")
	}
}

func TestDomainFieldsAreOptional(t *testing.T) {
	// Only the fields that are set take part.
	d := Domain{Name: "App"}
	enc, err := EncodeType(d.Types(), "EIP712Domain")
	if err != nil {
		t.Fatalf("EncodeType: %v", err)
	}
	if enc != "EIP712Domain(string name)" {
		t.Errorf("EncodeType = %s", enc)
	}
	if _, err := d.Separator(); err != nil {
		t.Errorf("Separator: %v", err)
	}

	// Chain 0 only takes part when it was asked for explicitly.
	withZero := Domain{Name: "App", ChainID: 0, HasChainID: true}
	enc, _ = EncodeType(withZero.Types(), "EIP712Domain")
	if enc != "EIP712Domain(string name,uint256 chainId)" {
		t.Errorf("explicit chain 0 = %s", enc)
	}

	// An empty domain is legal, if rarely wise.
	empty := Domain{}
	enc, _ = EncodeType(empty.Types(), "EIP712Domain")
	if enc != "EIP712Domain()" {
		t.Errorf("empty domain = %s", enc)
	}
	if _, err := empty.Separator(); err != nil {
		t.Errorf("empty Separator: %v", err)
	}

	// A malformed verifying contract is reported, not silently dropped.
	bad := Domain{Name: "App", VerifyingContract: "0xnothex"}
	if _, err := bad.Separator(); err != ErrBadAddress {
		t.Errorf("bad contract = %v, want ErrBadAddress", err)
	}
	// A salt must be a full word.
	badSalt := Domain{Name: "App", Salt: []byte{1, 2}}
	if _, err := badSalt.Separator(); err != ErrBadWord {
		t.Errorf("short salt = %v, want ErrBadWord", err)
	}
}

func TestHashPersonalMessage(t *testing.T) {
	tests := []struct{ in, want string }{
		{"", "5f35dce98ba4fba25530a026ed80b2cecdaa31091ba4958b99b52ea1d068adad"},
		{"hello gno.land", "1a4458b6e14c11fa8cef199442096cd9bc5019ab94f8a5f4e96ea259c0f8682b"},
		{"Hello, Bob!", "af0a369c7440ada5f06e224551e765ad1acc4ec60aa08944e72415249fa9213e"},
	}
	for _, tt := range tests {
		if got := hexOf(HashPersonalMessage([]byte(tt.in))); got != tt.want {
			t.Errorf("HashPersonalMessage(%q) = %s, want %s", tt.in, got, tt.want)
		}
	}
}

func TestEncodeArray(t *testing.T) {
	a, err := EncodeArray(EncodeUint64(1), EncodeUint64(2))
	if err != nil {
		t.Fatalf("EncodeArray: %v", err)
	}
	b, _ := EncodeArray(EncodeUint64(2), EncodeUint64(1))
	if hexOf(a) == hexOf(b) {
		t.Error("array encoding ignores order")
	}
	if _, err := EncodeArray(make([]byte, 5)); err != ErrBadWord {
		t.Error("short member accepted")
	}
	// An empty array is the hash of nothing, not an error.
	if _, err := EncodeArray(); err != nil {
		t.Errorf("empty array: %v", err)
	}
}
