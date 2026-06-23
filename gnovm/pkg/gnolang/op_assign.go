package gnolang

func (m *Machine) doOpDefine() {
	s := m.PopStmt().(*AssignStmt)
	// Define each value evaluated for Lhs.
	// NOTE: PopValues() returns a slice in
	// forward order, not the usual reverse.
	rvs := m.PopValues(len(s.Lhs))
	m.incrCPU(OpCPUSlopeDefine * int64(len(s.Lhs)))
	lb := m.LastBlock()
	for i := range s.Lhs {
		// Get name and value of i'th term.
		nx := s.Lhs[i].(*NameExpr)
		// Finally, define (or assign if loop block).
		ptr := lb.GetPointerToMaybeHeapDefine(m.Store, nx)
		if m.Stage != StagePre && isUntyped(rvs[i].T) && rvs[i].T.Kind() != BoolKind {
			panic("untyped conversion should not happen at runtime")
		}
		ptr.Assign2(m, m.Alloc, m.Store, m.Realm, rvs[i], true)
	}
}

func (m *Machine) doOpAssign() {
	s := m.PopStmt().(*AssignStmt)
	// Assign each value evaluated for Lhs.
	// NOTE: PopValues() returns a slice in
	// forward order, not the usual reverse.
	rvs := m.PopValues(len(s.Lhs))
	m.incrCPU(OpCPUSlopeAssign * int64(len(s.Lhs)))
	for i := len(s.Lhs) - 1; 0 <= i; i-- {
		// b[i] = x into a Data-backed byte slice/array writes the byte in
		// place, skipping the per-assignment DataByteValue pointer box.
		if ix, ok := s.Lhs[i].(*IndexExpr); ok {
			m.assignToIndex(ix, rvs[i])
			continue
		}
		// Pop lhs value and desired type.
		lv := m.PopAsPointer(s.Lhs[i])
		if m.Stage != StagePre && isUntyped(rvs[i].T) && rvs[i].T.Kind() != BoolKind {
			panic("untyped conversion should not happen at runtime")
		}
		lv.Assign2(m, m.Alloc, m.Store, m.Realm, rvs[i], true)
	}
}

// assignToIndex performs `x[i] = rv`, popping the index and container operands
// the IndexExpr lvalue left on the stack (same order as PopAsPointer2). For a
// Data-backed byte slice/array it writes the byte straight into the backing
// array, skipping the heap-allocated DataByteValue pointer box the general path
// materializes per assignment; DidUpdate then marks the array dirty and
// enforces cross-realm write permissions, matching Assign2's DataByteType
// branch. Maps and every other container defer to the shared pointerAtIndex.
func (m *Machine) assignToIndex(ix *IndexExpr, rv TypedValue) {
	iv := m.PopValue()
	xv := m.PopValue()
	if m.Stage != StagePre && isUntyped(rv.T) && rv.T.Kind() != BoolKind {
		panic("untyped conversion should not happen at runtime")
	}
	if xv.T.Kind() != MapKind {
		if base, idx, ok := xv.dataByteTarget(m.Store, int(iv.ConvertGetInt())); ok {
			if m.IsReadonly(xv) {
				m.Panic(typedString(readonlyAccessPanic(ix)))
			}
			base.Data[idx] = rv.GetUint8()
			m.Realm.DidUpdate(m, base, nil, nil)
			return
		}
	}
	pv, ro := m.pointerAtIndex(ix, xv, iv)
	if ro {
		m.Panic(typedString(readonlyAccessPanic(ix)))
	}
	pv.Assign2(m, m.Alloc, m.Store, m.Realm, rv, true)
}

func (m *Machine) doOpAddAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	// Per-N gas for BigInt/BigDec.
	m.incrCPUBigInt(lv.TV, rv, OpCPUSlopeBigIntAdd)
	m.incrCPUBigDec(lv.TV, rv, OpCPUSlopeBigDecAdd)

	// add rv to lv.
	addAssign(m.Alloc, lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpSubAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	m.incrCPUBigInt(lv.TV, rv, OpCPUSlopeBigIntSub)
	m.incrCPUBigDec(lv.TV, rv, OpCPUSlopeBigDecSub)

	// sub rv from lv.
	subAssign(lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpMulAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	m.incrCPUBigIntQuad(lv.TV, rv, OpCPUSlopeBigIntMulQ)
	m.incrCPUBigDecQuad(lv.TV, rv, OpCPUSlopeBigDecMulQ)

	// lv *= rv
	mulAssign(lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpQuoAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	m.incrCPUBigIntQuad(lv.TV, rv, OpCPUSlopeBigIntQuoQ)
	m.incrCPUBigDecQuad(lv.TV, rv, OpCPUSlopeBigDecQuoQ)

	// lv /= rv
	err := quoAssign(lv.TV, rv)
	if err != nil {
		panic(err)
	}

	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpRemAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	m.incrCPUBigIntQuad(lv.TV, rv, OpCPUSlopeBigIntRemQ)

	// lv %= rv
	err := remAssign(lv.TV, rv)
	if err != nil {
		panic(err)
	}

	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpBandAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	m.incrCPUBigInt(lv.TV, rv, OpCPUSlopeBigIntBand)

	// lv &= rv
	bandAssign(lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpBandnAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	m.incrCPUBigInt(lv.TV, rv, OpCPUSlopeBigIntBandn)

	// lv &^= rv
	bandnAssign(lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpBorAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	m.incrCPUBigInt(lv.TV, rv, OpCPUSlopeBigIntBor)

	// lv |= rv
	borAssign(lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpXorAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])
	if debug {
		debugAssertSameTypes(lv.TV.T, rv.T)
	}

	m.incrCPUBigInt(lv.TV, rv, OpCPUSlopeBigIntXor)

	// lv ^= rv
	xorAssign(lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpShlAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])

	// Per-N gas for BigInt Shl: charge per-kilobit of shift amount.
	if lv.TV.T == UntypedBigintType {
		m.incrCPU(int64(rv.GetUint()) * OpCPUSlopeBigIntShl / 1024)
	}

	// lv <<= rv
	shlAssign(m, lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}

func (m *Machine) doOpShrAssign() {
	s := m.PopStmt().(*AssignStmt)
	rv := m.PopValue() // only one.
	lv := m.PopAsPointer(s.Lhs[0])

	m.incrCPUBigUnary(lv.TV, OpCPUSlopeBigIntShr)

	// lv >>= rv
	shrAssign(m, lv.TV, rv)
	if lv.Base != nil {
		m.Realm.DidUpdate(m, lv.Base.(Object), nil, nil)
	}
}
