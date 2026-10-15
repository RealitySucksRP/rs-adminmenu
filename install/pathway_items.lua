-- RS Pathways inventory item examples. Copy ONLY the block for your inventory provider.
-- The item is a display/launcher; possession never grants certification.

-- ox_inventory: add inside ox_inventory/data/items.lua
-- ['citizen_guide'] = {
--     label = 'Citizen Orientation Card',
--     weight = 0,
--     stack = false,
--     close = true,
--     description = 'Official city orientation checklist.',
--     client = { export = 'rs-adminmenu.openPathwayGuide' }
-- },

-- QBCore/Qbox shared-item style example (for inventories using Shared.Items):
-- citizen_guide = {
--     name = 'citizen_guide',
--     label = 'Citizen Orientation Card',
--     weight = 0,
--     type = 'item',
--     unique = true,
--     useable = true,
--     shouldClose = true,
--     description = 'Official city orientation checklist.'
-- },
-- Note: Qbox commonly uses ox_inventory. For a custom/QB inventory, connect its usable-item
-- callback to TriggerServerEvent('rs-admin:pathways:guide', pathwayKey, false) from the client.


-- Additional ox_inventory cards for the included academy tracks:
-- ['police_guide'] = {
--     label = 'Police Academy Field Card', weight = 0, stack = false, close = true,
--     description = 'Official academy training checklist.',
--     client = { export = 'rs-adminmenu.openPathwayGuide' }
-- },
-- ['ems_guide'] = {
--     label = 'EMS Orientation Checklist', weight = 0, stack = false, close = true,
--     description = 'Official EMS orientation checklist.',
--     client = { export = 'rs-adminmenu.openPathwayGuide' }
-- },
