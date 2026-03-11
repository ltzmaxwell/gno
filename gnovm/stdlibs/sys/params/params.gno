package params

// SetSysParam*(module, submodule, name, value) sets VM-level system parameters.
// The key format is "module:submodule:name".
// Access to "sys/params" is restricted to gno.land/r/sys/params (governance realm).

func SetSysParamString(module, submodule, name string, val string) {
	setSysParamString(module, submodule, name, val)
}

func SetSysParamBool(module, submodule, name string, val bool) {
	setSysParamBool(module, submodule, name, val)
}

func SetSysParamInt64(module, submodule, name string, val int64) {
	setSysParamInt64(module, submodule, name, val)
}

func SetSysParamUint64(module, submodule, name string, val uint64) {
	setSysParamUint64(module, submodule, name, val)
}

func SetSysParamBytes(module, submodule, name string, val []byte) {
	setSysParamBytes(module, submodule, name, val)
}

func SetSysParamStrings(module, submodule, name string, val []string) {
	if val == nil {
		val = []string{}
	}
	setSysParamStrings(module, submodule, name, val)
}

func UpdateSysParamStrings(module, submodule, name string, val []string, add bool) {
	if val == nil {
		val = []string{}
	}
	updateSysParamStrings(module, submodule, name, val, add)
}

// SetRealmParam*(realmPath, name, value) lets governance set params in a
// specific realm's namespace.  The stored key is "vm:<realmPath>:<name>",
// identical to the format produced by std.SetParam* (chain/params), so
// governance and realms share the same key namespace.
//
// Use this to bootstrap or override realm-scoped params on behalf of a realm.

func SetRealmParamString(realmPath, name string, val string) {
	setRealmParamString(realmPath, name, val)
}

func SetRealmParamBool(realmPath, name string, val bool) {
	setRealmParamBool(realmPath, name, val)
}

func SetRealmParamInt64(realmPath, name string, val int64) {
	setRealmParamInt64(realmPath, name, val)
}

func SetRealmParamUint64(realmPath, name string, val uint64) {
	setRealmParamUint64(realmPath, name, val)
}

func SetRealmParamBytes(realmPath, name string, val []byte) {
	setRealmParamBytes(realmPath, name, val)
}

func SetRealmParamStrings(realmPath, name string, val []string) {
	if val == nil {
		val = []string{}
	}
	setRealmParamStrings(realmPath, name, val)
}

func setSysParamString(module, submodule, name string, val string)
func setSysParamBool(module, submodule, name string, val bool)
func setSysParamInt64(module, submodule, name string, val int64)
func setSysParamUint64(module, submodule, name string, val uint64)
func setSysParamBytes(module, submodule, name string, val []byte)
func setSysParamStrings(module, submodule, name string, val []string)
func updateSysParamStrings(module, submodule, name string, val []string, add bool)

func setRealmParamString(realmPath, name string, val string)
func setRealmParamBool(realmPath, name string, val bool)
func setRealmParamInt64(realmPath, name string, val int64)
func setRealmParamUint64(realmPath, name string, val uint64)
func setRealmParamBytes(realmPath, name string, val []byte)
func setRealmParamStrings(realmPath, name string, val []string)
