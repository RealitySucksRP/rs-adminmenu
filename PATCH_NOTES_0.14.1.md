# RS Adminmenu 0.14.1 — dock, previews, weapons and catalog

Date: 10-14-2026

This is an incremental fix on top of 0.14.0, **not** a repeat of the
0.14.0 two-client live acceptance. Existing configs, artwork, and saved data
are unchanged. No changes were made to rs-hvac or ox_inventory themselves.

## Changes

- **Dock/minimize and ped/object preview:** In DOCKED mode the full-screen
  tablet and its `#app::before` cinematic vignette no longer paint or intercept
  the gameplay area. Only the bottom-right RS Owner widget remains. Hidden
  overlays cannot intercept dock interactions. Hold **Alt** (the default dock
  interaction key) to use the dock, click its expand arrow, or use `/rsadmin`
  to reopen. Existing local preview entity creation/cleanup code is retained.
- **Weapons (Assets → Weapons):** On servers running ox_inventory, registered
  weapon items are delivered through the existing inventory adapter with
  starting-ammo metadata, rather than transient `GiveWeaponToPed` natives.
  Unregistered native/pseudo weapon entries are not offered. Targeted grants
  and self-grants share that same server-validated path, returning an explicit
  error if the item cannot be granted. The page now has live search and shows
  the configured delivery mode. On servers without ox_inventory, the existing
  native weapon handling remains in use.
- **Weapon tools:** Give All, Remove All and Max Ammo now use ox_inventory's
  registered weapons, inventory removals and weapon metadata respectively,
  when ox_inventory is active. Partial bulk grants are reported as granted vs
  skipped; do not interpret a partial result as an all-weapons success.
- **HVAC exclusions (Assets → Items):** HVAC part/equipment identifiers and
  recognizable HVAC labels are excluded from the admin **browse catalog**.
  This includes the previously visible aircon/rooftop units, filter/driers,
  contactors, fan motors, blower wheels and brazing supplies. Inventory item
  registrations, item possession, and resource-specific functionality are not
  modified. Other providers' missing images retain their normal fallback.

## Validation performed for this patch

- JavaScript syntax: `node --check web/app.js` — passed.
- Lua parsing: `server/main.lua`, `server/advanced.lua`, `server/framework.lua`
  passed local Lua parser checks.
- Chromium browser workspace mock, 1650 × 928: DOCKED mode transparent at two
  separate world-view pixels, visible dock at bottom-right, HIDDEN mode off,
  FULL mode restored, searchable weapon cards, no JavaScript exceptions.
- Lua handler fixture: ox_inventory registered weapon grant, unavailable
  weapon denial, bulk grant, inventory removal, max-ammo metadata with existing
  durability preserved, and non-ox native fallback — passed.
- Lua HVAC fixture: 9 previously visible items, 3 HVAC label variants and 7
  unrelated items — passed.

## Still requires live FiveM acceptance

1. In Qbox/Enhanced, minimize and expand both before and after previewing a ped
   or object, checking that the surrounding game remains visible.
2. Grant a registered weapon to yourself and a second character. Verify it
   appears in ox_inventory and survives normal unequip/re-equip and relog.
3. Test bulk grant only with disposable test inventory; it is constrained by
   real slot and weight limits. Test Remove All only on a disposable character.
4. Review the item catalog with a clear search. Check if there are additional
   server-specific rs-hvac identifiers; append explicit exclusions if required.

No live-client or full-server persistence claim is made for these 0.14.1 changes.
