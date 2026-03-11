package params

import (
	"strings"

	gno "github.com/gnolang/gno/gnovm/pkg/gnolang"
	"github.com/gnolang/gno/gnovm/stdlibs/internal/execctx"
)

// sysParamsRealm is the only realm allowed to call sys/params functions.
// This restriction will eventually be enforced via import rules instead.
const sysParamsRealm = "gno.land/r/sys/params"

// SetSysParam* functions set VM-level or module-level system parameters.
// The key format is "module:submodule:name".
// Access is restricted to gno.land/r/sys/params (governance realm).

func X_setSysParamString(m *gno.Machine, module, submodule, name, val string) {
	assertSysParamsRealm(m)
	pk := prmkey(module, submodule, name)
	execctx.GetContext(m).Params.SetString(pk, val)
}

func X_setSysParamBool(m *gno.Machine, module, submodule, name string, val bool) {
	assertSysParamsRealm(m)
	pk := prmkey(module, submodule, name)
	execctx.GetContext(m).Params.SetBool(pk, val)
}

func X_setSysParamInt64(m *gno.Machine, module, submodule, name string, val int64) {
	assertSysParamsRealm(m)
	pk := prmkey(module, submodule, name)
	execctx.GetContext(m).Params.SetInt64(pk, val)
}

func X_setSysParamUint64(m *gno.Machine, module, submodule, name string, val uint64) {
	assertSysParamsRealm(m)
	pk := prmkey(module, submodule, name)
	execctx.GetContext(m).Params.SetUint64(pk, val)
}

func X_setSysParamBytes(m *gno.Machine, module, submodule, name string, val []byte) {
	assertSysParamsRealm(m)
	pk := prmkey(module, submodule, name)
	execctx.GetContext(m).Params.SetBytes(pk, val)
}

func X_setSysParamStrings(m *gno.Machine, module, submodule, name string, val []string) {
	assertSysParamsRealm(m)
	pk := prmkey(module, submodule, name)
	execctx.GetContext(m).Params.SetStrings(pk, val)
}

func X_updateSysParamStrings(m *gno.Machine, module, submodule, name string, val []string, add bool) {
	assertSysParamsRealm(m)
	pk := prmkey(module, submodule, name)
	execctx.GetContext(m).Params.UpdateStrings(pk, val, add)
}

// SetRealmParam* functions let governance set params in a specific realm's
// namespace.  The key stored is "vm:<realmPath>:<name>", which is the same
// format used by std.SetParam* (chain/params).  This allows governance to
// bootstrap or override realm-scoped params on behalf of any realm.

func X_setRealmParamString(m *gno.Machine, realmPath, name, val string) {
	assertSysParamsRealm(m)
	pk := realmkey(m, realmPath, name)
	execctx.GetContext(m).Params.SetString(pk, val)
}

func X_setRealmParamBool(m *gno.Machine, realmPath, name string, val bool) {
	assertSysParamsRealm(m)
	pk := realmkey(m, realmPath, name)
	execctx.GetContext(m).Params.SetBool(pk, val)
}

func X_setRealmParamInt64(m *gno.Machine, realmPath, name string, val int64) {
	assertSysParamsRealm(m)
	pk := realmkey(m, realmPath, name)
	execctx.GetContext(m).Params.SetInt64(pk, val)
}

func X_setRealmParamUint64(m *gno.Machine, realmPath, name string, val uint64) {
	assertSysParamsRealm(m)
	pk := realmkey(m, realmPath, name)
	execctx.GetContext(m).Params.SetUint64(pk, val)
}

func X_setRealmParamBytes(m *gno.Machine, realmPath, name string, val []byte) {
	assertSysParamsRealm(m)
	pk := realmkey(m, realmPath, name)
	execctx.GetContext(m).Params.SetBytes(pk, val)
}

func X_setRealmParamStrings(m *gno.Machine, realmPath, name string, val []string) {
	assertSysParamsRealm(m)
	pk := realmkey(m, realmPath, name)
	execctx.GetContext(m).Params.SetStrings(pk, val)
}

// assertSysParamsRealm walks the call stack to find the first realm caller and
// asserts it is sysParamsRealm.  Walking is necessary because the immediate
// previous frame may be a non-call (label/block) frame.
//
// Once proper import-restriction rules exist this check can be removed, as the
// linker will prevent non-sysParamsRealm packages from importing sys/params.
func assertSysParamsRealm(m *gno.Machine) {
	for i := m.NumFrames() - 1; i >= 0; i-- {
		fr := &m.Frames[i]
		if !fr.IsCall() {
			continue
		}
		path := fr.LastPackage.PkgPath
		if !gno.IsRealmPath(path) {
			continue
		}
		// Found the first realm in the call stack.
		if path != sysParamsRealm {
			panic(`"sys/params" can only be called from "` + sysParamsRealm + `"`)
		}
		return
	}
	panic("sys/params: no realm caller found in call stack")
}

// prmkey formats and validates a three-part system parameter key.
// The resulting key has the form "module:submodule:name".
func prmkey(module, submodule, name string) string {
	if module == "" {
		panic("param module cannot be empty")
	}
	if strings.Contains(module, ":") {
		panic("invalid param module: " + module)
	}
	if submodule == "" {
		panic("param submodule cannot be empty")
	}
	if strings.Contains(submodule, ":") {
		panic("invalid param submodule: " + submodule)
	}
	if name == "" {
		panic("param name cannot be empty")
	}
	if strings.Contains(name, ":") {
		panic("invalid param name: " + name)
	}
	return module + ":" + submodule + ":" + name
}

// realmkey validates and formats a realm-scoped parameter key.
// The resulting key has the form "vm:<realmPath>:<name>", matching the format
// produced by std.SetParam* (chain/params) so governance and realms share the
// same key namespace.
func realmkey(m *gno.Machine, realmPath, name string) string {
	if !gno.IsRealmPath(realmPath) {
		m.PanicString("invalid realm path: " + realmPath)
	}
	if name == "" {
		m.PanicString("param name cannot be empty")
	}
	if strings.Contains(name, ":") {
		m.PanicString("invalid param name: " + name)
	}
	return "vm:" + realmPath + ":" + name
}
