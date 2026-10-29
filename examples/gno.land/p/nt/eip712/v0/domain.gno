package eip712

// Domain is the EIP712Domain separator's contents. Every field is optional:
// only the ones that are set take part, in the canonical order below, which
// is how wallets build the separator too.
//
// The domain is what stops a signature made for one application or one chain
// from being replayed against another, so leaving it empty is rarely right.
type Domain struct {
	Name              string
	Version           string
	ChainID           uint64
	VerifyingContract string // "0x" and 40 hex digits
	Salt              []byte // exactly 32 bytes when used

	// HasChainID distinguishes chain 0 from no chain at all. Chain 0 is not
	// a real network, so leaving this false is almost always what is meant.
	HasChainID bool
}

// Types returns the EIP712Domain declaration implied by the fields that are
// set, suitable for [EncodeType].
func (d Domain) Types() Types {
	fields := []Field{}
	if d.Name != "" {
		fields = append(fields, Field{Name: "name", Type: "string"})
	}
	if d.Version != "" {
		fields = append(fields, Field{Name: "version", Type: "string"})
	}
	if d.ChainID != 0 || d.HasChainID {
		fields = append(fields, Field{Name: "chainId", Type: "uint256"})
	}
	if d.VerifyingContract != "" {
		fields = append(fields, Field{Name: "verifyingContract", Type: "address"})
	}
	if len(d.Salt) != 0 {
		fields = append(fields, Field{Name: "salt", Type: "bytes32"})
	}
	return Types{"EIP712Domain": fields}
}

// Separator returns the domain separator: the hashStruct of EIP712Domain over
// the fields that are set.
func (d Domain) Separator() ([]byte, error) {
	types := d.Types()
	typeHash, err := TypeHash(types, "EIP712Domain")
	if err != nil {
		return nil, err
	}

	fields := [][]byte{}
	if d.Name != "" {
		fields = append(fields, EncodeString(d.Name))
	}
	if d.Version != "" {
		fields = append(fields, EncodeString(d.Version))
	}
	if d.ChainID != 0 || d.HasChainID {
		fields = append(fields, EncodeUint64(d.ChainID))
	}
	if d.VerifyingContract != "" {
		w, err := EncodeAddress(d.VerifyingContract)
		if err != nil {
			return nil, err
		}
		fields = append(fields, w)
	}
	if len(d.Salt) != 0 {
		w, err := EncodeWord(d.Salt)
		if err != nil {
			return nil, err
		}
		fields = append(fields, w)
	}
	return HashStruct(typeHash, fields...)
}
