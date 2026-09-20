package gnolang

import (
	"fmt"
	"maps"
	"slices"
)

// upgradePlan is what a versioned redeploy carries over from the package live
// at the path: every global, keyed to the heap item that persists it, and the
// shape of every declared type. Built while the prior package is still what
// the store serves; applied once the new one has replaced it.
type upgradePlan struct {
	vars  map[Name]carriedVar
	types map[Name]TypeID // declared type name -> TypeID of its underlying type
	prior *Block          // the prior package block, which still names the heap items
}

type carriedVar struct {
	oid   ObjectID // the *HeapItemValue holding the variable
	tid   TypeID   // the variable's static type
	index int      // its slot in the prior package block
}

// IsPkgInitFunc reports whether name is a package initializer: init, or
// migrate, its counterpart on a versioned redeploy. Both may be declared more
// than once, cannot be referenced, and run once at deploy.
func IsPkgInitFunc(name Name) bool {
	return name == "init" || name == "migrate"
}

// planUpgrade reads the package live at pkgPath.
func planUpgrade(store Store, pkgPath string) *upgradePlan {
	pv := store.GetPackage(pkgPath, false)
	if pv == nil {
		panic(fmt.Sprintf("upgrade: no package at %s", pkgPath))
	}
	pn := store.GetPackageNode(pkgPath)
	pb := pv.GetBlock(store)
	plan := &upgradePlan{
		vars:  map[Name]carriedVar{},
		types: map[Name]TypeID{},
		prior: pb,
	}
	heap := pn.GetHeapItems()
	for i, name := range pn.GetBlockNames() {
		if heap[i] {
			plan.vars[name] = carriedVar{
				oid:   pb.Values[i].V.(ObjectIDer).GetObjectID(),
				tid:   pn.GetStaticBlock().Types[i].TypeID(),
				index: i,
			}
		}
	}
	for _, dt := range ownDeclaredTypes(pb, pkgPath) {
		plan.types[dt.Name] = dt.Base.TypeID()
	}
	return plan
}

// ownDeclaredTypes returns the types pb declares for pkgPath. Aliases to
// uverse or other packages' types are left to their owner.
func ownDeclaredTypes(pb *Block, pkgPath string) []*DeclaredType {
	var dts []*DeclaredType
	for _, tv := range pb.Values {
		if tvv, ok := tv.V.(TypeValue); ok {
			if dt, ok := tvv.Type.(*DeclaredType); ok && dt.PkgPath == pkgPath {
				dts = append(dts, dt)
			}
		}
	}
	return dts
}

// applyUpgradePlan points the new package block at the heap items the prior
// version persisted, refusing any change the plan cannot carry. It runs after
// PrepareNewValues and before any declaration executes.
//
// The prior blocks are not deleted: their reference counts include every
// function and file block parented under them, which is the cleanup #4949
// is about. The prior block's slots for the carried heap items are cleared,
// so that cleanup cannot later count the live items as its own.
func (m *Machine) applyUpgradePlan(pn *PackageNode, pv *PackageValue, plan *upgradePlan) {
	store := m.Store
	pb := pv.GetBlock(store)

	// Types first: the heap items loaded below resolve their TypeIDs through
	// the store and must see this version's definitions, methods included.
	seen := map[Name]struct{}{}
	for _, dt := range ownDeclaredTypes(pb, pv.PkgPath) {
		seen[dt.Name] = struct{}{}
		if old, ok := plan.types[dt.Name]; ok && old != dt.Base.TypeID() {
			panic(fmt.Sprintf("upgrade: type %s changed its underlying type; "+
				"a versioned redeploy may change methods, not a type's shape", dt.Name))
		}
	}
	if name, ok := missingName(plan.types, seen); ok {
		panic(fmt.Sprintf("upgrade: type %s was removed; persisted values may still have it", name))
	}
	m.saveDeclaredTypes(pv, true)

	clear(seen)
	heap := pn.GetHeapItems()
	for i, name := range pn.GetBlockNames() {
		cv, ok := plan.vars[name]
		if !ok {
			continue
		}
		seen[name] = struct{}{}
		if !heap[i] {
			panic(fmt.Sprintf("upgrade: %s is no longer a variable", name))
		}
		if tid := pn.GetStaticBlock().Types[i].TypeID(); tid != cv.tid {
			panic(fmt.Sprintf("upgrade: variable %s changed type from %s to %s; "+
				"declare the new one under another name and migrate", name, cv.tid, tid))
		}
		hiv := store.GetObject(cv.oid).(*HeapItemValue)
		// Detach from the prior block; finalize re-adopts it under the new one.
		hiv.DecRefCount()
		hiv.SetOwner(nil)
		pb.Values[i] = TypedValue{T: heapItemType{}, V: hiv}
		plan.prior.Values[cv.index] = TypedValue{}
	}
	if name, ok := missingName(plan.vars, seen); ok {
		panic(fmt.Sprintf("upgrade: global %s was removed; keep it declared, or migrate in two steps", name))
	}
	pv.GetRealm().MarkDirty(plan.prior)
}

// missingName returns the smallest name in want that have lacks.
func missingName[V any](want map[Name]V, have map[Name]struct{}) (Name, bool) {
	for _, n := range slices.Sorted(maps.Keys(want)) {
		if _, ok := have[n]; !ok {
			return n, true
		}
	}
	return "", false
}

// isCarriedDecl reports whether decl declares carried globals, refusing a
// declaration that mixes carried and new names.
func isCarriedDecl(decl Decl, plan *upgradePlan) bool {
	vd, ok := decl.(*ValueDecl)
	if !ok || plan == nil {
		return false
	}
	n := 0
	for _, nx := range vd.NameExprs {
		if _, ok := plan.vars[nx.Name]; ok {
			n++
		}
	}
	switch n {
	case 0:
		return false
	case len(vd.NameExprs):
		return true
	default:
		panic(fmt.Sprintf("upgrade: declaration %v mixes carried and new globals", vd.GetDeclNames()))
	}
}
