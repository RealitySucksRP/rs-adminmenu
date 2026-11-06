RS AdminMenu

Free, full-source FiveM administration and world-control resource from RealitySucksRP.

Installation

1. Place the folder named `rs-adminmenu` in your server's `resources` directory.
2. Configure `config.lua` for your framework and server preferences. Review `server_config.lua` for optional **server-only** webhook settings; keep real webhook URLs private.
3. Add owner ACE permissions to `server.cfg`. Use `server.cfg.example` as the editable reference. Replace `REPLACE_ME` with the owner's **actual** license identifier.
4. Enable OneSync and ensure your framework and selected providers are started before this resource.
5. Add `ensure rs-adminmenu` to `server.cfg` and start or restart the server.

Example owner setup (replace the placeholder):

```cfg
set onesync on
add_principal identifier.license:REPLACE_ME group.rsowner
add_ace group.rsowner rsadmin.owner allow
add_ace group.rsowner rsadmin.all allow
ensure rs-adminmenu
```

**Commands and keys:** `/rsadmin` or F7 opens the tablet; `/fadminmenu` or F10 opens the quick menu; `/aduty` toggles admin duty. Key mappings may be reassigned through FiveM settings.

Features

- Admin tablet with player list, selected-player controls, live operations map, moderation, reports, staff roles and audit logs.
- Player spectate, teleport, healing, revival, punishments and owner/developer tools with server-side permission checks.
- Vehicles, items, catalogs, garage/provider integration, asset builder, and configurable dashboard widgets.
- Weather, time, population and server controls. Owner-pinned weather persists once configured and can be released from the tablet.
- Disaster scenarios: moving tornado with a particle funnel, hurricane gusts, debris, optional flying cows, angled meteors with rock and fire trails, cinematic craters, debris and owner-authorized impacts, and optional collision-based cinematic vehicle impacts.
- Optional custom pathways with hooks and item templates in `install/`. Do not add those templates to a provider unless using that integration.

Disaster settings and safety

Open **World → Disasters**. Disasters affect the **Entire Server** and use the existing server permission checks. Depending on the hazard, adjustable settings include duration, intensity, wind heading, radius, lift, storm movement, entity physics and impact options.

The active event shows its name, remaining time and initiating staff member. Owner stop controls are at the top of the storm panel. **Stop Current Disaster** ends that event and restores the underlying weather. **Stop + Restore Normal** also cancels tsunami maintenance and clears saved weather, time and population overrides. A saved permanent weather pin is separate from an event timer.

Jail and community service resume after the server confirms the selected character has loaded. New community-service sentences belong to that character. Old account-based records remain in Service History, marked for review or release; they are not assigned automatically to another character. Community service cycles through five configured digging spots in the Bolingbroke prison yard, each with its own coordinates and facing direction. Press **E** at the highlighted spot to dig with a shovel; **X** cancels without deducting a task. The server checks identity, duration and proximity. Change `Config.Punishments.communityServiceSpots` (`x`, `y`, `z`, `w` heading) and `communityServiceTask` to customize the locations, label, duration, animation dictionary/clip, scenario and prop for other chores. The first spot is the arrival point. Existing configurations using `communityServiceCoords` with `communityServiceOffsets` remain supported when no absolute spots are configured.

Target weapon removal and Strip use the active inventory provider. With ox_inventory, weapon items are removed from their slots; unrelated items remain intact. Provider failures are reported.

Owners can review unresolved transfers in **Server → Economy → Transfer Recovery**. Failed or uncertain transfers retain a recovery ID and block further admin changes to the affected account. Check provider balances and complete any necessary correction before recording a resolution note. Recording a resolution does not move money. Uncertain outcomes are never retried automatically.

The resource distinguishes cinematic **client-local stunt vehicles and objects** from real server-owned or player-owned vehicles. Advanced physical impacts and verified empty-traffic destruction have additional server permission and safety conditions. Do not enable destructive modes on a populated production server without testing.

Meteor impact damage is enabled for eligible ambient NPCs and unowned traffic verified by the configured vehicle registry. Stored, occupied, unverified and mission vehicles are protected. Player damage remains disabled by default; to opt in, set `Config.Disasters.meteor.damagePlayers = true` and `Config.Disasters.allowDamage = true`. The event creator remains exempt from meteor impact damage. Meteor craters are timed ground-surface effects, not permanent changes to road collision or geometry.

Legacy and Enhanced builds may differ in DLC model availability, particle behavior, physics and collision results. Tornadoes and hurricanes are scripted effects, not real fluid simulations; existing static world trees and buildings are not destructible. Storm-surge water XML is experimental and may need a restart to restore the map's water state completely.

Frameworks and compatibility

- Qbox/QBX, QBCore, ESX and standalone support are provided through included adapters where implemented. Provider-specific features require a working corresponding framework/inventory/garage/keys/fuel resource.
- **OneSync is required.** The manifest enforces this dependency.
- `ox_lib` may be used by compatible providers, but no separate RealitySucksRP library is required by this package.
- Resource uses the included NUI under `web/`. The UI stays hidden until opened.

Custom pictures

- Optional item images: put files in `web/assets/items/`, using an item's name such as `advancedlockpick.webp`.
- Optional custom vehicle images: put files in `web/assets/vehicles/`, using the vehicle spawn/model name such as `rs_customcar.webp`.
- Keep the included tablet frame, concept art, wallpapers, map image and entity catalog; the UI and catalog tools reference them.

Preserving live server data

The downloadable package deliberately omits generated runtime JSON files (staff, bans, reports, logs, sessions, statistics, saved weather, and recovery snapshots). The resource initializes empty state on a new install and saves live data under `data/`. **When upgrading, preserve the existing server's `rs-adminmenu/data/` directory**, especially any current bans, staff assignments and persistent weather. The included `data/entity_catalog.json` is a static lookup asset, not a player record.

Source and license

Distributed free of charge with readable source. See `LICENSE` for free-use and non-resale terms. Third-party media, trademarks and assets are subject to their own terms; do not assume the code license grants rights to independently owned images or other content.

The bundled 6144 × 9216 satellite map is a cropped and optimized local derivative of GTA V World Map by Zslash / Martin Floden. See `THIRD_PARTY_NOTICES.txt` for source and permission details. This adapted map is bundled locally for the operations map, with coordinates calibrated to the source tile grid and the exact bundled image crop. Map controls: scroll or +/− to zoom, drag to pan, ◎ to center the selected player, and FIT to show the complete map. The map uses a flat overhead HD view. Nearby vehicles are grouped into numbered markers; click a group to choose an individual vehicle, or hover a single marker for its plate.

The operations map displays that atlas as 54 local 1024-pixel tiles under `web/assets/map-tiles/`. Keep this directory when updating. Player refreshes update markers without replacing the map tiles; zoom resizes the map plane directly to retain detail without scaling vehicle markers.

Player and vehicle markers use the same crop-aware coordinate projection. The source tile calibration follows the documented w3w-map projection reference.
