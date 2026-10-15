local service=nil
local choreIndex=1
local offsets={{4.0,0.0},{-4.0,2.0},{2.0,5.0},{-2.5,-4.0},{5.5,-2.0}}
local function notify(msg) if RSAdmin and RSAdmin.Notify then RSAdmin.Notify(msg) end end
local function coords() local c=(service and service.coords) or {}; return vector3(tonumber(c.x) or 170.18,tonumber(c.y) or -990.91,tonumber(c.z) or 30.09) end
local function teleportBase() local c=coords(); SetEntityCoords(PlayerPedId(),c.x,c.y,c.z+0.2,false,false,false,false); if service and service.coords and service.coords.w then SetEntityHeading(PlayerPedId(),service.coords.w+0.0) end end
RegisterNetEvent('rs-admin:client:communityService',function(d) service=d; if type(d.offsets)=='table' and #d.offsets>0 then offsets=d.offsets end; choreIndex=math.max(1,math.min(#offsets,tonumber(d.choreIndex) or choreIndex)); teleportBase(); notify(('Community service: %s tasks remaining. %s'):format(d.remaining or 0,d.reason or '')) end)
RegisterNetEvent('rs-admin:client:communityServiceStop',function(d) service=nil; ClearPedTasksImmediately(PlayerPedId()); notify((d and d.reason) or 'Community service ended.') end)
CreateThread(function()
    while true do
        if not service then Wait(1000) else
            local ped=PlayerPedId(); local base=coords(); local p=GetEntityCoords(ped); local dx,dy,dz=p.x-base.x,p.y-base.y,p.z-base.z
            if dx*dx+dy*dy+dz*dz>2500.0 then teleportBase(); p=GetEntityCoords(ped) end
            local off=offsets[choreIndex]; local x,y,z=base.x+off[1],base.y+off[2],base.z
            DrawMarker(1,x,y,z-1.0,0,0,0,0,0,0,1.2,1.2,.25,32,169,255,125,false,false,2,false,nil,nil,false)
            local ax,ay,az=p.x-x,p.y-y,p.z-z
            if ax*ax+ay*ay+az*az<3.0 then
                BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(('Press ~INPUT_CONTEXT~ to complete task · %s remaining'):format(service.remaining or 0)); EndTextCommandDisplayHelp(0,false,true,-1)
                if IsControlJustReleased(0,38) then
                    TaskStartScenarioInPlace(ped,'WORLD_HUMAN_JANITOR',0,true); Wait(3200); ClearPedTasks(ped)
                    RSAdmin.RPC('communityService:complete',{id=service.id},function(r) if r and r.ok then if r.data.remaining<=0 then service=nil else service.remaining=r.data.remaining; choreIndex=math.max(1,math.min(#offsets,tonumber(r.data.choreIndex) or choreIndex)) end else notify(r and r.error or 'Task failed') end end)
                    Wait(400)
                end
            end
            Wait(0)
        end
    end
end)
