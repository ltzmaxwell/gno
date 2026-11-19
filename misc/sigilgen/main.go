// Command sigilgen turns a CSV of "address,amount" lines into the Merkle root
// that r/ltzmaxwell/sigil commits to, plus one claim line per entry. It must
// hash exactly like p/nt/merkleproof: AirdropLeaf, sorted pairs, odd node
// carried up.
//
//	go run ./misc/sigilgen < list.csv
package main

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"strings"

	"golang.org/x/crypto/sha3"
)

func keccak(b []byte) []byte {
	h := sha3.NewLegacyKeccak256()
	h.Write(b)
	return h.Sum(nil)
}

func leaf(index uint64, addr string, amount int64) []byte {
	var buf []byte
	buf = binary.BigEndian.AppendUint64(buf, index)
	buf = binary.BigEndian.AppendUint16(buf, uint16(len(addr)))
	buf = append(buf, addr...)
	buf = binary.BigEndian.AppendUint64(buf, uint64(amount))
	return keccak(keccak(buf))
}

func pair(a, b []byte) []byte {
	if bytes.Compare(a, b) > 0 {
		a, b = b, a
	}
	return keccak(append(append([]byte{}, a...), b...))
}

func build(leaves [][]byte) [][][]byte {
	levels := [][][]byte{leaves}
	for l := leaves; len(l) > 1; {
		var next [][]byte
		for i := 0; i+1 < len(l); i += 2 {
			next = append(next, pair(l[i], l[i+1]))
		}
		if len(l)%2 == 1 {
			next = append(next, l[len(l)-1])
		}
		levels = append(levels, next)
		l = next
	}
	return levels
}

func proof(levels [][][]byte, i int) string {
	var out []string
	for d := 0; d < len(levels)-1; d++ {
		if s := i ^ 1; s < len(levels[d]) {
			out = append(out, hex.EncodeToString(levels[d][s]))
		}
		i /= 2
	}
	return strings.Join(out, ",")
}

func main() {
	var addrs []string
	var amounts []int64
	var leaves [][]byte
	var total int64
	sc := bufio.NewScanner(os.Stdin)
	for n := 1; sc.Scan(); n++ {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		a, v, ok := strings.Cut(line, ",")
		amt, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
		if !ok || err != nil || amt <= 0 || !strings.HasPrefix(strings.TrimSpace(a), "g1") {
			fmt.Fprintf(os.Stderr, "line %d: want \"g1address,positive amount\"\n", n)
			os.Exit(1)
		}
		a = strings.TrimSpace(a)
		leaves = append(leaves, leaf(uint64(len(addrs)), a, amt))
		addrs, amounts = append(addrs, a), append(amounts, amt)
		total += amt
	}
	if len(leaves) == 0 {
		fmt.Fprintln(os.Stderr, "empty list")
		os.Exit(1)
	}
	levels := build(leaves)
	fmt.Printf("root %s\ntotal %d\n", hex.EncodeToString(levels[len(levels)-1][0]), total)
	for i := range addrs {
		// Claim(id, index, amount, proof), called by addrs[i]
		fmt.Printf("claim %s %d %d %s\n", addrs[i], i, amounts[i], proof(levels, i))
	}
}
