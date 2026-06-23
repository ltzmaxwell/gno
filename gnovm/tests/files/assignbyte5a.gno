package main

import "filetests/extern/copytest"

// assignbyte5a — `b[i] = x` into an external-realm, Data-backed *named* byte
// slice (type NamedBytes []byte) still resolves through baseOf to the byte-write
// fast path, so the readonly-taint check must guard it like the unnamed case
// (assignbyte5).

func main() {
	copytest.DataNamedByteSlice[0] = 9

	println("OK")
}

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): (const (ref(filetests/extern/copytest) package{})).DataNamedByteSlice[(const (0 int))]
