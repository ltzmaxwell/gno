package gnolang

import (
	"testing"
)

// Regression test for fix 1: DelAttribute on nil data should not panic.
// Previously, debug mode panicked with "attribute is expected to be non-empty".
func TestDelAttribute_NilData(t *testing.T) {
	var attr Attributes // attr.data is nil
	// Should not panic.
	attr.DelAttribute(ATTR_PREPROCESSED)
}

// Regression test for fix 2: GetLocalIndex with nil Source should not panic.
// Previously, debug mode called reflect.TypeOf(nil).String() which panics.
func TestGetLocalIndex_NilSource(t *testing.T) {
	sb := &StaticBlock{}
	// Source is nil, should not panic in debug Printf.
	_, ok := sb.GetLocalIndex("nonexistent")
	if ok {
		t.Error("expected false for nonexistent name")
	}
}

// Regression test for fix 3: Define2 with generic InterfaceType should not panic.
// Previously, calling TypeID() on a generic InterfaceType (e.g. <X>{}) panicked.
func TestDefine2_GenericInterfaceType(t *testing.T) {
	// Use a FuncLitExpr as a real BlockNode.
	fn := &FuncLitExpr{}
	fn.InitStaticBlock(fn, nil)

	genType := &InterfaceType{Generic: "X"}
	tv := TypedValue{T: genType}

	// First define.
	fn.Define2(false, Name("x"), genType, tv, NameSource{})

	// Redefine with the same generic type — should not panic.
	fn.Define2(false, Name("x"), genType, tv, NameSource{})
}
