package main

import "filetests/extern/copytest"

// assignbyte5 — `b[i] = x` into an external-realm, Data-backed []byte takes the
// byte-write fast path (op_assign.go assignToIndex), which writes straight into
// the backing array, bypassing Assign2. The readonly-taint check must still
// guard it, just like the copy() byte fast path (copy5e) and append.

func main() {
	copytest.DataByteSlice[0] = 9

	println("OK")
}

// Error:
// cannot directly modify readonly tainted object (use a method or crossing function): (const (ref(filetests/extern/copytest) package{})).DataByteSlice[(const (0 int))]
