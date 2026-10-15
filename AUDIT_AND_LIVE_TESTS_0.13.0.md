# rs-adminmenu 0.13.0 — Audit and live evidence

October 14, 2026. Target: Enhanced FiveM, Qbox, active ox_inventory and rs-garage. This was a focused source audit, UI repair and single-client live pass. It is not a full compatibility or production certification.

## What caused the empty, disconnected UI

1. Empty subsection navigation disappeared from CSS grid auto-placement. The main content occupied the 44 px subsection row and was clipped. Content and footer now have explicit grid rows.
2. The document click handler used `closest('[data-page]')`. The root app itself has `data-page`, so every interior click was consumed as page navigation before item selection or action dispatch. It now selects only navigation buttons.
3. The 20 existing operator powers had no dedicated Command workspace. The new workspace exposes their existing client actions with a current server permission check.
4. Tablet constraints forced many controls to 8–10 px. The interface now occupies a responsive landscape workspace. Live inspection at 3840 × 2160 exposed a width cap; viewport scaling fixes it.
5. Live requests for newly split workspace files returned 404. The final implementation is bundled into the existing app.js and style.css. No build step or new library is needed.

## Changes

- Dashboard: visible tool groups, incident queue, action history, live overview and existing configurable widgets.
- Command: movement, recovery, vision, combat, vehicle and weapon groups; 20 existing power switches and utility controls.
- Players: roster, selected-player profile, refreshed health/armor/death/laststand, 15 permission-filtered quick actions, and atlas positions.
- Assets: paginated provider catalogs, selection/details, favorites, grid/list views and filters scoped explicitly to the current page; weapon library uses configured server weapons. No fictitious item-definition editor was added.
- Theme: eight illustrated palette cards, wallpaper gallery, existing typography/motion controls and preferences.
- Focus: periodic refresh does not replace an actively edited search/form input; content and roster scroll positions are retained.
- Medical: conscious healing clears Qbox wounds and restores native HP; death/laststand routes through qbx_medical Revive. A running Qbox with an unavailable medical provider fails instead of silently falling back to incompatible native recovery.
- Garage discovery: the included adapter reads rs-garage getAllGarages and identifies it in provider status. Existing vehicle-grant/owned-vehicle contracts are preserved; no real vehicle ownership transaction was executed in this pass.
- Client data exposure: removed data/*.json from manifest files. Server LoadResourceFile storage remains intact. Live NUI fetches for audit.json, staff.json and bans.json returned 404.
- Fixed the JavaScript `nil` reference in the inventory remove-one action.

The new map is an unchanged copy of the existing rs-tablet atlas (SHA-256 DFB1D9C95B8278CACB0BA3D1DD6018E568EF12858F1BB7C4B3FAD6481DC4E0D3). It uses the sibling phone's world bounds and a common plane for image and markers. On the connected live client, the new local atlas returned 404 despite refresh/restart, while the already-running tablet atlas returned 200. The fallback was exercised live; a fresh standalone client using the bundled atlas remains an acceptance check. Geographic calibration at multiple known landmarks remains to be checked in game.

## Verification

| Check | Evidence / result |
| --- | --- |
| Lua 5.4 compilation | All 27 Lua files passed real Lua 5.4 load/compile. |
| JSON | All 27 data/locale JSON files parsed. |
| JavaScript | node --check passed. |
| Browser workspaces | 60 workspace/layout cases passed without JavaScript errors or horizontal main-content overflow. Viewports: 1680 × 945, 1920 × 1080, 1280 × 720, 800 × 600, 3840 × 2160. |
| Browser interactions | Item selection/details, favorite filtering, list view, power switch state, noclip/reset state, search typing across a polling interval, and hidden-root state passed. These are preview tests, not gameplay proofs. |
| Server fixture | 12 authority/medical dispatch assertions passed, including denied ordinary staff, denied unknown actions, unavailable target, conscious heal, laststand routing, provider failure and standalone fallback. Providers/natives were mocked. |
| Garage fixture | Active rs-garage list discovery and sorting passed. |
| Live opening | Owner bootstrap succeeded in real CEF with PREVIEW=false, operator identity and Qbox data. |
| Live navigation | Command, Players, item/vehicle catalogs, World, Theme and provider status rendered. No JavaScript exceptions during captured checks. |
| Live data | Item catalog returned 1,540 registered items. Resource list returned 117 resources. A sultan vehicle search returned four results. Counts reflect this session, not fixed catalog sizes. |
| Live item selection | Actual item card populated target/amount/reason and give/remove controls. No inventory mutation was performed. |
| Live medical | Conscious healSelf returned success through operator:heal and the medical-provider path. Dead/laststand recovery was not exercised live. |
| Live garage list | Bootstrap returned 38 configured garages; bridge status identified rs-garage as started. |
| Live authorization | Known operator action accepted; an unknown operator action returned Unknown operator action. A second, unprivileged client is still required for real negative permission testing. |
| Live lifecycle | close/expand callbacks hid and reopened the menu; several user-triggered resource restarts loaded the edited resource. Restart with every power/effect active remains untested. |

Working files, baseline backup, SHA-256 inventory, scripts, browser-results.json, live-smoke.json and screenshots are stored in `C:\zap1342458\g689259\fivem\_rs-adminmenu-audit\20261014`. The baseline was captured before gameplay/source edits. The server.cfg startup entry was originally commented out; the user enabled it during the live session. This handoff does not replace server.cfg or configs.

## Remaining confirmed findings

| Priority | Finding | Consequence / validation needed |
| --- | --- | --- |
| P1 | server/advanced.lua:372–377 checks only the driver seat when deciding a vehicle is occupied. | Cleanup can delete a vehicle containing passengers with no driver. Ownership lookup failure/unavailable qbx_vehicles is also treated as unowned; nearby cleanup has no bucket filter. Global cleanup was not executed. |
| P2 | server/main.lua:524 and 551 persist reporter as a transient source ID, then reply to whoever currently holds that ID. | A historical response can be delivered to another player after reconnect/source reuse. Bind reports to persistent identity before relying on historical direct replies. No live messages to other players were sent. |
| P2 | server/main.lua:27–35 clears dirty persistence before checking SaveResourceFile's result. | Failed disk writes silently lose the pending update; one-second batching remains a crash boundary. Failure/recovery and crash durability need repair/testing. |
| P2 | client/world_control.lua continuously reasserts its default weather/time on every client. | Can compete with other weather/time controllers even before an owner changes World controls. Coexistence with active weather providers remains untested. |

Additional limits: multi-client spectate/buckets, occupied/owned cleanup, real inventory/economy/vehicle transactions, reports with reconnects, jail/service recovery, pathways/rewards, high-water restoration, resource-stop cleanup with powers active, Legacy and alternate framework/provider paths remain open. Some registered inventory items lack provider images; the UI shows IMAGE UNAVAILABLE instead of using an unrelated concept screenshot. CPU/RAM percentages are not fabricated.

## Exact handoff files

- fxmanifest.lua
- web/app.js
- web/style.css
- web/assets/map.webp
- client/main.lua
- client/powers.lua
- server/main.lua
- server/advanced.lua
- server/framework.lua
- server/bridge.lua
- README.md
- TEST_REPORT.md
- AUDIT_AND_LIVE_TESTS_0.13.0.md

No saved data, inventory definitions, server startup file, existing artwork, water files or user configs are included in the changed-files handoff. Normal live resource activity may update its own data files; those writes are not patch files.

## References

User-supplied artwork guided the layout. Feature coverage was compared with [ps-adminmenu](https://github.com/Project-Sloth/ps-adminmenu), [vMenu](https://github.com/TomGrobbe/vMenu), and [LGF_AdminMenu](https://github.com/ENT510/LGF_AdminMenu); [LGF_Utility](https://github.com/Legacy-Scripts/LGF_Utility) was reviewed as a utility/UI library. No code from those projects was copied, and none was added as a runtime dependency. Their feature lists are references, not a claim that every one of their features has been implemented here.

### LGF_AdminMenu comparison

Reviewed its README and source components Panel.tsx, entitySpawner.tsx, rapidAction.tsx and executorConsole.tsx. The repository describes itself as unfinished and requires LGF_Utility. Its entity browser uses bundled vehicle/ped/object JSON catalogs; its panel separates tools into explicit tabs. The comparison below describes this resource's current implementation rather than claiming drop-in compatibility.

| LGF workflow | rs-adminmenu location / coverage | Acceptance or remaining difference |
| --- | --- | --- |
| Dashboard logs and entity counts | Dashboard / Logs; real online staff and vehicle counts | Live summary rendered; no full ped/object world counter was added. |
| Player list and map | Players: roster, atlas, profile, quick actions | Live owner profile/map rendered; map landmark calibration and multi-client actions remain open. |
| Vehicle browser and spawn | Assets > Vehicles; Vehicles > Catalog / Give | Live model search and card selection worked; ownership grants were not executed. |
| Ped/object model browser | World > Builder; Assets > Entities lists saved placements | Existing model-name placement remains available. A searchable illustrated ped/object model catalog is still missing. |
| Inventory browser / add | Assets > Items and selected-item give/remove forms | Live registered-item catalog and selection worked; actual mutations were not exercised. |
| Resource manager | Server > Resources | Live list returned actual resource states; lifecycle mutations were not executed during this comparison. |
| Raycast/entity debugging | Command > Entity laser and coordinate tools | Existing tools are exposed; this is not the full LGF entity-debug editor. |
| Code runner | No in-menu code editor | Not implemented in this release. |

Final follow-up inspection of the connected 3840 × 2160 CEF session found the menu visible, no horizontal content overflow, and 46 controls in Command. No JavaScript exceptions were observed during that check. The screenshot live-command.png records the actual running menu.
