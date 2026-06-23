// recover25c — OOB on a byte-slice WRITE (`b[i] = x` via the dataByteTarget
// fast path in op_assign.go) must be recoverable, just like recover25/recover25b
// cover the read side.

package main

var b = []byte{1, 2, 3, 4}

func main() {
	defer func() {
		r := recover()
		println("recover:", r)
	}()
	i := 7
	b[i] = 9
}

// Output:
// recover: runtime error: slice index out of bounds: 7 (len=4)
