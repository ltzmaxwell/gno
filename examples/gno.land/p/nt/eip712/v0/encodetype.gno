package eip712

import (
	"crypto/keccak256"
	"errors"
	"sort"
	"strconv"
	"strings"
)

var (
	// ErrUnknownType is returned when a type name is neither a declared
	// struct nor an EIP-712 atomic or dynamic type.
	ErrUnknownType = errors.New("eip712: unknown type")
	// ErrNoSuchStruct is returned when the primary type is not declared.
	ErrNoSuchStruct = errors.New("eip712: no such struct type")
	// ErrEmptyFieldName is returned for a field with no name.
	ErrEmptyFieldName = errors.New("eip712: field has no name")
	// ErrCircularType is returned when struct types reference each other in
	// a cycle, which EIP-712 cannot encode.
	ErrCircularType = errors.New("eip712: circular type reference")
)

// Field is one member of a struct type.
type Field struct {
	Name string
	Type string
}

// Types declares the struct types a message uses, keyed by struct name. Its
// iteration order is never relied on: dependencies are collected by walking
// fields and are then sorted by name, as the spec requires.
type Types map[string][]Field

// EncodeType returns the canonical type string for primary, for example
//
//	Mail(Person from,Person to,string contents)Person(string name,address wallet)
//
// The primary type comes first and every struct it reaches, directly or
// through a member, follows sorted by name. Two messages agree on a signature
// only if they agree on this string exactly.
func EncodeType(types Types, primary string) (string, error) {
	if _, ok := types[primary]; !ok {
		return "", ErrNoSuchStruct
	}
	deps, err := dependencies(types, primary)
	if err != nil {
		return "", err
	}

	var b strings.Builder
	if err := writeStruct(&b, types, primary); err != nil {
		return "", err
	}
	for _, name := range deps {
		if name == primary {
			continue
		}
		if err := writeStruct(&b, types, name); err != nil {
			return "", err
		}
	}
	return b.String(), nil
}

// TypeHash returns keccak256 of the string [EncodeType] produces.
func TypeHash(types Types, primary string) ([]byte, error) {
	enc, err := EncodeType(types, primary)
	if err != nil {
		return nil, err
	}
	sum := keccak256.Sum256([]byte(enc))
	return sum[:], nil
}

func writeStruct(b *strings.Builder, types Types, name string) error {
	b.WriteString(name)
	b.WriteString("(")
	for i, f := range types[name] {
		if f.Name == "" {
			return ErrEmptyFieldName
		}
		if err := checkType(types, f.Type); err != nil {
			return err
		}
		if i > 0 {
			b.WriteString(",")
		}
		b.WriteString(f.Type)
		b.WriteString(" ")
		b.WriteString(f.Name)
	}
	b.WriteString(")")
	return nil
}

// dependencies returns every struct type reachable from primary, sorted by
// name.
func dependencies(types Types, primary string) ([]string, error) {
	found := map[string]bool{}
	var walk func(name string, depth int) error
	walk = func(name string, depth int) error {
		if found[name] {
			return nil
		}
		if depth > len(types) {
			return ErrCircularType
		}
		found[name] = true
		for _, f := range types[name] {
			base := baseType(f.Type)
			if _, ok := types[base]; ok {
				if err := walk(base, depth+1); err != nil {
					return err
				}
			}
		}
		return nil
	}
	if err := walk(primary, 0); err != nil {
		return nil, err
	}

	out := make([]string, 0, len(found))
	for name := range found {
		out = append(out, name)
	}
	sort.Strings(out)
	return out, nil
}

// baseType strips any array suffix: "Person[]" and "uint256[3]" become
// "Person" and "uint256".
func baseType(t string) string {
	if i := strings.Index(t, "["); i >= 0 {
		return t[:i]
	}
	return t
}

// checkType rejects a field type that is neither a declared struct nor a
// valid EIP-712 primitive, which catches a typo that would otherwise be
// silently encoded as an unknown atomic type.
func checkType(types Types, t string) error {
	base := baseType(t)
	if _, ok := types[base]; ok {
		return nil
	}
	if !isAtomic(base) {
		return ErrUnknownType
	}
	// Validate any array suffix: "[]" or "[<decimal>]".
	rest := t[len(base):]
	for rest != "" {
		if !strings.HasPrefix(rest, "[") {
			return ErrUnknownType
		}
		end := strings.Index(rest, "]")
		if end < 0 {
			return ErrUnknownType
		}
		if inner := rest[1:end]; inner != "" {
			n, err := strconv.Atoi(inner)
			if err != nil || n <= 0 {
				return ErrUnknownType
			}
		}
		rest = rest[end+1:]
	}
	return nil
}

// isAtomic reports whether t is one of EIP-712's own types: address, bool,
// string, bytes, bytes1..bytes32, and uint/int in 8-bit steps up to 256.
func isAtomic(t string) bool {
	switch t {
	case "address", "bool", "string", "bytes":
		return true
	}
	if n, ok := suffixSize(t, "bytes"); ok {
		return n >= 1 && n <= 32
	}
	if n, ok := suffixSize(t, "uint"); ok {
		return n%8 == 0 && n >= 8 && n <= 256
	}
	if n, ok := suffixSize(t, "int"); ok {
		return n%8 == 0 && n >= 8 && n <= 256
	}
	return false
}

func suffixSize(t, prefix string) (int, bool) {
	if !strings.HasPrefix(t, prefix) {
		return 0, false
	}
	digits := t[len(prefix):]
	if digits == "" {
		return 0, false
	}
	n, err := strconv.Atoi(digits)
	if err != nil {
		return 0, false
	}
	return n, true
}
