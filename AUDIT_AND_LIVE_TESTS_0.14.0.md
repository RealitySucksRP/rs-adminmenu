# rs-adminmenu 0.14.0 — audit repairs and live acceptance

Validated on October 14, 2026 against the active Enhanced FiveM/Qbox resource. This follows the cinematic UI audit in `AUDIT_AND_LIVE_TESTS_0.13.0.md`; that file remains a historical baseline.

## Changes

- Assets adds searchable, categorized, paginated ped and object catalogs: 1,066 ped models and 21,298 object models. Selection feeds the existing World Builder workflow. Preview is local, singular, non-colliding and removed on close, replacement or resource stop. Models unavailable in the current game build return an error. These are model catalogs, not rendered thumbnail libraries.
- Server adds an owner-only client/server Lua editor with per-scope saved drafts and output. Every run rechecks server authorization. Execution uses an explicit native API; file/process/HTTP/resource access, dynamic loading, asynchronous threads and `goto` are unavailable. Source and output have limits; loop and function boundaries enforce a budget. CfxLua lacks `debug.sethook`, so the initial hook-based implementation was replaced after reproducing its failure live. This editor is for trusted owners; it is not an isolated VM or a universal resource executor.
- Tornado adds a shared server-selected origin, eight rotating smoke particle layers, rain, wind and camera effects. Optional vehicle forces require owner permission and apply only to a bounded set of verified unowned, empty nearby vehicles with matching identities. Hurricane provides thunder, rain, wind, lightning and camera effects. Damage and tornado vehicle forces were disabled during acceptance. These are game simulations, not a meteorological system.
- Storm expiry is enforced by server wall time and character identity, in addition to the client timer. Live testing reproduced delayed client expiry on the two-client setup; the server expiry repair passed the repeat check. Stop/replacement/resource stop remove tracked effects.
- Weather presets release manual rain to the native weather system. Atmosphere and density controls use separate payloads. Legacy weather commands update the same server state. The resource owns only fields explicitly changed, begins with no overrides and exposes `IsWorldControlled`. Release clears its claims. UI metrics say SERVER when the resource has no weather/time claim.
- Cleanup excludes occupants including passengers, player-owned vehicles, unknown ownership, other buckets and out-of-range vehicles. It rechecks identity and occupancy after potentially yielding ownership queries. Ownership-provider failure skips vehicles rather than assuming they are disposable.
- Reports bind account plus character identity. Replies resolve the current matching session, never a stale source ID. Legacy reports without identity remain offline for routing; internal identity is stripped from client responses.
- JSON writes retain failures for retry, verify saved bytes by readback, warn when acknowledgement precedes durability, and preserve a last valid recovery snapshot. Invalid/missing primary JSON can recover from that snapshot. Critical state writes immediately. Snapshots are not an OS-level atomic transaction or an external backup.
- Jail identity uses Qbox character citizen ID, preventing Bruce and Jamie sharing an account from sharing a sentence. Old account-keyed jail entries remain in the saved file for review and explicit release; they are not automatically assigned to a different character.
- Player labels prefer character names. Qbox owned-vehicle rows expose `props.plate` at the top level for the existing UI. Server console `rsadmin <source>` opens the menu for an authorized player through normal bootstrap.

## Real live results

Bruce Lee was source 1. The second character's stored name is Jamie Rooss, source 2. Both clients were connected simultaneously through the existing bounded localhost gate.

| Acceptance path | Observed result |
| --- | --- |
| Client Lua | Printed native health 200 and returned source 1; source 2 execution returned 2 |
| Server Lua | Printed two connected players and returned requesting source 1 |
| Infinite loop | Returned Execution budget exceeded; menu remained responsive |
| Catalog search | Ped `cop` returned 8 matches; object `tool_box` returned 22 |
| Entity previews | Ped `a_m_m_business_01` and object `prop_tool_box_04` created successfully and cleared |
| Heal Jamie | Health 175 to 200 through Qbox medical path |
| Bring Jamie | Arrived within 3 metres of Bruce; Bruce remained in place |
| Give item | Water increased from 4 to 5 |
| Give owned car | Sultan, plate RSFA182, vehicle ID 56, saved to Pillbox Garage; owned list increased from 2 to 3 and persisted across restart |
| Jail Jamie | Entered configured cell near 459.6, -997.9, 24.9; sentence bound to Jamie's character and survived resource restart |
| Release Jamie | Arrived at configured release point; sentence recorded released; Jamie then restored to original Paleto Bay location |
| Report | Jamie created a report; Bruce replied to Jamie and closed it; client response omitted private identity |
| Tornado on both clients | Both reported THUNDER, rain 0.6 and 8 valid particle handles |
| Hurricane on both clients | Both reported THUNDER and rain 1 |
| Storm expiry | Repeat test cleared disaster state and all particle handles on both clients, restored pre-event weather type and released wind |
| Weather presets | RAIN and THUNDER produced native rainfall; EXTRASUNNY returned rain to zero |
| Manual atmosphere | Native rain approximately 0.65 and wind 7 |
| Density isolation/release | Density change preserved rain; release left no owned fields and restored wind to zero |
| Cleanup dry run | Radius 5 at Bruce's location returned zero candidates; no production vehicles deleted |

The water and Sultan grants are retained as authorized gifts. The test jail is released, test reports are closed and weather overrides are released. The localhost gate is closed after testing; its established limit remains 60 minutes with two distinct characters. The memory update records that workflow separately from this resource.

## Automated evidence

- Lua 5.4 syntax and JSON parsing; JavaScript syntax.
- 63 browser workspace/layout cases, including 4K; 12 additional responsive catalog/editor layouts; draft preservation, selection handoff, owner tab filtering and atmosphere payload checks.
- Actual handler fixtures cover owner denial, source/character reuse and reconnect report routing, legacy reports, persistence failure/retry/acknowledgement and recovery of corrupt primary JSON.
- Cleanup fixtures cover passenger-only occupancy, ownership-provider failure/unavailability, owned vehicles, buckets, distance and a passenger arriving during a yielding query.
- Lua fixtures cover while/repeat loops, recursion, anonymous functions, quoted/long-string/comment preservation, unsupported goto, source limits and denied process/dynamic loading.

Evidence scripts/results are saved outside the resource in `C:/zap1342458/g689259/fivem/_rs-adminmenu-audit/20261014`. They are not installed as production scripts.

## Remaining validation limits

- Both local clients inherit owner privileges through the existing account setup. Non-owner execution denial passed actual-handler fixtures, not a third unprivileged live-client test.
- Report disconnect/source-reuse cases, unavailable ownership providers, passenger races and disk failure/recovery were fixture-tested, not induced on the live server. No live global cleanup was run.
- Tornado particle existence and cleanup passed; destructive forces, owner migration, damage and final funnel appearance from multiple camera angles still need controlled acceptance. Hurricane is an atmosphere simulation.
- Weather claims/release and storm restoration passed here. A controller that continuously overwrites the same native fields needs an explicit integration using the ownership export; universal third-party weather arbitration is not claimed. Native rain may fade during release.
- Garage storage/ownership passed; retrieving and driving the newly granted Sultan through the garage UI remains untested.
- Full server crash/reconnect, long-running multi-hour soak, Legacy/QBCore/ESX parity and cold-client atlas acceptance remain untested.
- Inventory artwork missing from the active ox_inventory image folder uses IMAGE UNAVAILABLE. Those provider assets were not replaced.

## Changed-files handoff

The 0.14.0 archive is cumulative against the original audit baseline: 23 files. Configs, saved player/business/admin JSON, existing artwork and startup files are excluded. `data/entity_catalog.json` is the sole packaged data file and contains static model facts. Config and existing-art hashes are checked against the baseline; ZIP entries are checked against current source hashes.

Files: `fxmanifest.lua`, `web/app.js`, `web/style.css`, `web/assets/map.webp`, `client/main.lua`, `client/powers.lua`, `client/world_control.lua`, `client/devtools.lua`, `shared/lua_console.lua`, `server/main.lua`, `server/advanced.lua`, `server/framework.lua`, `server/bridge.lua`, `server/devtools.lua`, `server/operations.lua`, `server/staff_groups.lua`, `server/punishments.lua`, `server/pathways.lua`, `data/entity_catalog.json`, `README.md`, `TEST_REPORT.md`, `AUDIT_AND_LIVE_TESTS_0.13.0.md`, `AUDIT_AND_LIVE_TESTS_0.14.0.md`.
