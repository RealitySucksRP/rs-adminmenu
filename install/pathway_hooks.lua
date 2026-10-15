-- RS Pathways integration examples (SERVER-SIDE ONLY).
-- Copy the relevant call into the server-side success path of your provider/resource.
-- Do not expose a generic client event that completes Pathway steps.

-- Inventory opened successfully:
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'inventory_open', {})

-- Bank account created/opened successfully:
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'bank_account_opened', {})

-- Garage / vehicle lifecycle:
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'garage_opened', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'vehicle_retrieved', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'vehicle_stored', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'vehicle_refueled', {})

-- Appearance / emotes:
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'clothing_opened', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'emote_used', {})

-- Police academy examples:
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'police_duty', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'police_radio', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'police_armory', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'police_vehicle', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'police_cuff_training', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'police_report', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'police_supervisor_approved', {})

-- EMS examples:
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'ems_duty', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'ems_uniform', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'ems_radio', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'ems_vehicle', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'ems_treatment', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'ems_transport', {})
-- exports['rs-adminmenu']:ReportPathwayEvent(source, 'ems_report', {})

-- Gate another server action using certification:
-- if not exports['rs-adminmenu']:HasPathwayCertification(source, 'citizen') then
--     return -- deny the protected server-side action
-- end
