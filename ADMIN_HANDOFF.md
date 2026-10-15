# rs-adminmenu v0.9.1 — Engineering handoff

## Product rule

Top navigation is the primary workflow. Contextual drawers/panels are allowed; do not restore a permanent left navigation. Cinematic art remains the shell/background, with real NUI text/buttons/data on top.

## Server modules

- `server/main.lua` — RPC router, core permissions/rate limits, common player/item/vehicle/report operations, buffered persistence.
- `server/advanced.lua` — player profiles/stats, economy, jail, bans, widgets, logs, world/disasters, builder, catalog paging, vehicle cleanup.
- `server/player_actions.lua` — explicit player/vehicle quick actions.
- `server/punishments.lua` — warnings, community service, notes, watchlist.
- `server/staff_groups.lua` — persistent custom groups and rank-aware assignment.
- `server/bridge.lua` — provider status and custom property hook.
- `server/operations.lua` — duty, report lifecycle, channel chat, vehicle map, owned-vehicle DB, resources, quick prefs, scheduled cleanup and tsunami maintenance.

## Client modules

- `client/main.lua` — NUI bridge + RPC timeout cleanup.
- `client/quick_menu.lua` — F10 `/fadminmenu`, duty/channel pushes.
- `client/player_actions.lua` — explicit target actions.
- `client/punishments.lua` — reconnect-safe community-service client state.
- `client/powers.lua` / `noclip.lua` / `spectate.lua` / `entity_laser.lua` — curated native admin powers.
- `client/pranks.lua` — prank/effect execution and cleanup.
- `client/world_control.lua` — native world state/disaster application and tsunami water stages.
- `client/vehicle_lab.lua` — cached vehicle catalog + dynamic mod inspection.

## Security invariants

1. Every privileged RPC is re-authorized server-side.
2. Lower staff cannot modify equal/higher staff groups or protected Owner targets.
3. Money/inventory/owned-vehicle writes never trust NUI state.
4. Dangerous global disasters and global cleanup require elevated authority and UI confirmation.
5. Resource start/stop/restart obey a protected-resource guard.
6. NUI never receives an arbitrary native/Lua/SQL executor.
7. High-volume data is paginated/lazy.
8. RPC callbacks expire instead of accumulating.

## Tsunami maintenance

`maintenance:tsunamiStart` is Owner-only and deliberately separate from `disaster:start{name='tsunami'}`. It provides a countdown, announcements, starts the tsunami shortly before the maintenance boundary, and can optionally disconnect non-staff at the end. `maintenance:cancel` cancels the sequence. This makes tsunami usable as a visible RP evacuation/maintenance event without silently turning the normal disaster button into a mass disconnect.

## Provider/bridge policy

Qbox remains first priority. Use supported provider exports whenever practical. Custom housing/property schemas use `Config.BridgeHooks.properties`. Additional custom providers should be integrated through bridge hooks/adapters rather than hard dependencies.

## Live-map policy

Player and world-vehicle map data is refreshed on a controlled interval, not every frame. Perspective mode is a tactical 3D-style NUI transform, not a fake claim of full GTA terrain rendering.

## Next live gate

Do not market every provider-specific feature until it passes the live matrix in `TEST_REPORT.md`, especially garage/keys/fuel, housing, addon vehicle DBs, weather-sync conflicts and tsunami restoration.
