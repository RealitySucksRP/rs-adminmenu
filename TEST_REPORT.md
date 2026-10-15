## RS Resource Doctor 0.9.1 repair pass

- `server/main.lua`: forward-declared `audit` before the `DATA` table and converted the later declaration to assignment. `DATA.audit` was already a named table field rather than a runtime read of the function, but this removes ambiguity for static analyzers and preserves behavior.
- `server/advanced.lua`: removed the server-side `IsEntityDead` call. Player dead-state fallback now derives from the server-readable health value (`health <= 0`).
- Re-run static syntax and endpoint/wiring validation after both changes before packaging.

# Current continuation — October 15, 2026, v0.14.2 plus live fixes

See [LIVE_TEST_2026-10-15.md](LIVE_TEST_2026-10-15.md) for current two-client results, garage-provider repair, shared weather/time synchronization, inventory weapon delivery, dock/preview acceptance and remaining limits. Passenger-only cleanup, garage retrieval/drive and unprivileged-client acceptance remain unverified live.

# rs-adminmenu v0.13.0 — Historical test report

The current evidence and remaining audit findings are recorded in [AUDIT_AND_LIVE_TESTS_0.13.0.md](AUDIT_AND_LIVE_TESTS_0.13.0.md).

- 27 Lua 5.4 files and 27 JSON files passed; JavaScript syntax passed.
- 60 browser workspace/layout cases passed at five viewport sizes including 4K, plus interaction/focus checks.
- Server permission/medical dispatch and garage discovery fixtures passed.
- Real Enhanced FiveM/Qbox single-client NUI, owner bootstrap, navigation, catalogs, profile, garage list, provider status, conscious self-heal and close/reopen callbacks were exercised.
- Cleanup safety, report source-ID reuse, unchecked persistence failures, weather-provider coexistence and multiplayer acceptance remain open. This is not production certification.

---

# Historical rs-adminmenu v0.9.1 — Test Report

## Static gate completed

- Lua 5.4 syntax: **22 files passed**.
- JSON/locale parse: **25 files passed**.
- JavaScript syntax: passed.
- Literal NUI RPC wiring: **110 calls, 0 missing handlers**.
- Literal local actions: **13 calls, 0 missing handlers**.
- High-volume catalogs/history remain lazy or paginated.
- Protected-resource checks exist for resource management.
- Scheduled cleanup and tsunami-maintenance endpoints are Owner-authorized.

## Required live FiveM tests

### Stability

1. Open/close F9 repeatedly while watching F8/server logs and `resmon`.
2. Leave menu open 15+ minutes; verify pending RPCs/counters do not grow.
3. Profile Players map, vehicle-map mode, catalogs, logs, duty, staff channels and disasters.
4. Restart `rs-adminmenu` with powers/world effects active and verify cleanup.

### Player/profile

Verify player search, profile, inventory, owned vehicles, properties hook, history, playtime, health/armor/dead state, job/gang and every quick action.

### Jail

Test configured cell selection, minutes/hours/days, reason, reconnect resume, leash, expiry, unjail and history.

### Economy

Test cash/bank add/remove/set, transfers, max transfer, daily limit, high-value threshold, before/after balances and webhooks.

### Staff

Test rank/color/position, custom group create/edit/clone/delete, equal/higher-role protection, duty logs and staff-chat channel access/create/clear/delete.

### Reports

Test status filters, claim, in-context reply, close, reopen, Owner delete and reporter quick actions.

### Items / vehicles

Test provider images, item give/remove reasons, base/addon vehicle images, configured owned-vehicle grant, Vehicle Lab, owned-vehicle DB lookup/delete and keys/garage/fuel integration.

### Live map

Test player and world-vehicle modes with 20+ entities, flat/perspective transform, owner/driver labels, bucket differences and refresh cadence.

### Cleanup

Test dry run, immediate global cleanup and scheduled cleanup. Confirm occupied and owned vehicles survive. Confirm warnings and cancellation.

### World/disasters

Test each weather state, densities and disaster preset locally before global use. Confirm bounds/cleanup.

### Tsunami / maintenance

1. Ordinary tsunami must **not** disconnect players.
2. Owner-only maintenance sequence must show countdown announcements.
3. Verify tsunami lead-in timing.
4. Test cancellation before the boundary.
5. Test optional non-staff disconnect; verify configured staff remain connected when enabled.
6. Restart resource/server after high-water state and verify water restoration.

### Resource management

Verify protected resources cannot be stopped/restarted. Confirm Owner-only start/stop and configured restart permissions.

## Release gate

Release-ready status requires live evidence on the target Qbox server and at least the advertised compatibility/provider paths. Static validation alone is not a production claim.
