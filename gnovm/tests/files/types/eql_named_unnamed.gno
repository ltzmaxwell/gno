package main

type P struct{ X int }
type Arr [2]int
type Ptr *int

func main() {
	// A named type compares equal to its unnamed form: the unnamed operand
	// is converted to the named type before the runtime compares them.
	p := P{1}
	q := struct{ X int }{1}
	println(p == q, q == p, p != q)

	var a Arr = Arr{1, 2}
	b := [2]int{1, 2}
	println(a == b, b == a)

	i := 5
	var pp Ptr = &i
	up := &i
	println(pp == up, up == pp)
}

// Output:
// true true false
// true true
// true true
