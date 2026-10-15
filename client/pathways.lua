-- Player-facing RS Pathways tracking. Display only; the server owns progression.
local currentBlip=nil
local hud=nil

local function feed(title,msg)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('~b~%s~s~\n%s'):format(tostring(title or 'PATHWAYS'),tostring(msg or '')))
    EndTextCommandThefeedPostTicker(false,false)
end

RegisterNetEvent('rs-admin:client:pathwayNotify',function(d)
    feed(d and d.title or 'PATHWAYS',d and d.message or '')
end)

local function clearRoute()
    if currentBlip and DoesBlipExist(currentBlip) then RemoveBlip(currentBlip) end
    currentBlip=nil
end

RegisterNetEvent('rs-admin:client:pathwayRoute',function(d)
    if not d or not d.x or not d.y then return end
    clearRoute()
    SetNewWaypoint(tonumber(d.x)+0.0,tonumber(d.y)+0.0)
    currentBlip=AddBlipForRadius(tonumber(d.x)+0.0,tonumber(d.y)+0.0,tonumber(d.z or 0)+0.0,math.max(5.0,tonumber(d.radius) or 12.0))
    SetBlipColour(currentBlip,3);SetBlipAlpha(currentBlip,80)
    feed('NEXT OBJECTIVE',('%s\nGPS route updated.'):format(tostring(d.label or 'Objective')))
end)

RegisterNetEvent('rs-admin:client:pathwayObjective',function(d)
    if d and d.step then feed(tostring(d.label or 'PATHWAY'),('Next: %s'):format(tostring(d.step.label or 'Objective'))) end
end)

RegisterNetEvent('rs-admin:client:pathwayStatus',function(d)
    local s=d and d.state or {}; local step=s.currentStep
    local text=('%s\n%s / %s points · %s / %s steps'):format(tostring(s.label or 'Pathway'),tostring(s.points or 0),tostring(s.requiredPoints or 0),tostring(s.completedCount or 0),tostring(s.totalSteps or 0))
    if step then text=text..('\nNext: %s'):format(tostring(step.label or 'Objective')) end
    feed('PATHWAY STATUS',text)
    hud={state=s,untilAt=GetGameTimer()+12000}
end)

-- ox_inventory item definition can call this export. It requests read-only server state.
exports('openPathwayGuide',function(data)
    local meta=(data and (data.metadata or data)) or {}
    TriggerServerEvent('rs-admin:pathways:guide',meta.pathway or '',false)
end)

RegisterCommand('pathwaygps',function(_,args)
    local cfg=Config.Pathways or {}
    if cfg.Enabled~=true or (cfg.Tracking and cfg.Tracking.GPS==false) or (cfg.GPS and cfg.GPS.AllowPlayerRoute==false) then return end
    TriggerServerEvent('rs-admin:pathways:guide',args[1] or '',true)
end,false)

CreateThread(function()
    while true do
        if hud and Config.Pathways and Config.Pathways.Enabled and Config.Pathways.MiniHUD and Config.Pathways.MiniHUD.Enabled and GetGameTimer()<hud.untilAt then
            Wait(0)
            local s=hud.state or {}; local label=('%s  %s/%s'):format(tostring(s.label or 'Pathway'),tostring(s.points or 0),tostring(s.requiredPoints or 0))
            SetTextFont(4);SetTextScale(.0,.32);SetTextColour(235,245,255,225);SetTextOutline();SetTextEntry('STRING');AddTextComponentString(label);DrawText(.018,.79)
        else Wait(350) end
    end
end)

AddEventHandler('onResourceStop',function(r) if r==GetCurrentResourceName() then clearRoute() end end)
