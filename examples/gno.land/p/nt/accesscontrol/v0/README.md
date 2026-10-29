# accesscontrol

Role-based access control: named roles, each with an admin who may grant and
revoke it.

```go
roles := accesscontrol.NewRole("editor", admin)
rs.GrantRole(0, cur, "editor", account)
rs.RevokeRole(0, cur, "editor", account)
rs.RenounceRole(0, cur, "editor")       // called by the holder
```

Use it when `ownable` is too coarse — several capabilities, each held by a
different set of accounts — and `ownable` when one principal governs
everything.

Events are emitted for every change: `RoleCreatedEvent`, `RoleGrantedEvent`,
`RoleRevokedEvent`, `RoleRenouncedEvent`, `RoleSetEvent`. See `doc.gno` for
their keys.

## Status

v0, unaudited. Promoted from `p/thox/accesscontrol`.
